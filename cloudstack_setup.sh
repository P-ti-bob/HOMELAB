#!/usr/bin/env bash
set -euox pipefail

######################################
##### My Automated Homelab setup #####
######################################

cd "$(dirname "$0")"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)
NIX_USER=dyslexia
WAIT_TIMEOUT=300                 # seconds to wait for SSH, k3s and nodes
KUBECONFIG_FILE=hosts/kubeconfig # hosts/ is gitignored, this file contains cluster admin credentials

for cmd in tofu jq nix sops nc ssh kubectl helm helmfile; do
  command -v "$cmd" >/dev/null || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

##################################
##### Cloudstack VM creation #####
##################################
trap 'rm -f terraform/.plan' EXIT
tofu -chdir=terraform init
tofu -chdir=terraform plan -out=.plan
tofu -chdir=terraform apply .plan
mapfile -t IPs < <(tofu -chdir=terraform output -json vm_ips | jq -r '.[]') # output format = [homelab-0, homelab-1, homelab-2]

#############################
##### Age keys creation #####
#############################
keys_changed=false
for h in "${!IPs[@]}"; do
  host="homelab-$h"
  key_file="hosts/$host/etc/ssh/ssh_host_ed25519_key"

  mkdir -p "hosts/$host/etc/ssh"
  if [ ! -f "$key_file" ]; then
    ssh-keygen -q -t ed25519 -N "" -C "$host" -f "$key_file"
    age_key="$(nix run nixpkgs#ssh-to-age <"$key_file.pub")"
    echo "$host: new age key $age_key"

    # replace the &homelabN value in .sops.yaml
    sed -i -E "s|^(  - &homelab$h +)age1[a-z0-9]+|\1$age_key|" .sops.yaml
    grep -q "$age_key" .sops.yaml || {
      echo "Failed to update &homelab$h in .sops.yaml" >&2
      exit 1
    }
    keys_changed=true
  fi
done

# re-encrypt secrets so the new hosts can decrypt them
if $keys_changed; then
  for f in nixos/secrets/*.yaml; do
    sops updatekeys -y "$f"
  done
fi

#########################
##### NixOS install #####
#########################
# wait_until <description> <command...> : retry command every 2s until it succeeds or WAIT_TIMEOUT is reached
wait_until() {
  local desc=$1 waited=0
  shift
  until "$@" &>/dev/null; do
    if ((waited >= WAIT_TIMEOUT)); then
      echo "Timed out waiting for $desc" >&2
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

wait_for_ssh() {
  wait_until "SSH on $1" nc -z -w 2 "$1" 22
}

is_nixos() {
  ssh "${SSH_OPTS[@]}" "$NIX_USER@$1" 'test -e /etc/NIXOS' 2>/dev/null
}

for h in "${!IPs[@]}"; do
  host="homelab-$h"
  ip="${IPs[$h]}"

  echo "Waiting for SSH on $host ($ip)"
  wait_for_ssh "$ip"

  if is_nixos "$ip"; then
    echo "$host ($ip) already runs NixOS, skipping install"
    #apply config changes instead of reinstalling
    NIX_SSHOPTS="${SSH_OPTS[*]}" nix run nixpkgs#nixos-rebuild \
      --extra-experimental-features "nix-command flakes" \
      -- switch --flake "./nixos#$host" \
      --target-host "$NIX_USER@$ip" --use-remote-sudo
  else
    echo "Installing NixOS on $host ($ip)"
    nix run github:nix-community/nixos-anywhere \
      --extra-experimental-features "nix-command flakes" \
      -- --flake "./nixos#$host" \
      --extra-files "hosts/$host" \
      --target-host "debian@$ip"
  fi
done

###############################
##### Helm charts install #####
###############################
server_ip="${IPs[0]}" # homelab-0 is the k3s clusterInit server

kubeconfig_ready() {
  ssh "${SSH_OPTS[@]}" "$NIX_USER@$server_ip" 'test -s /etc/rancher/k3s/k3s.yaml'
}

all_nodes_joined() {
  [ "$(kubectl get nodes --no-headers | wc -l)" -ge "${#IPs[@]}" ]
}

echo "Waiting for k3s on homelab-0 ($server_ip)"
wait_for_ssh "$server_ip"
wait_until "k3s kubeconfig on homelab-0" kubeconfig_ready

# k3s always writes 127.0.0.1 in its kubeconfig, point it to homelab-0
ssh "${SSH_OPTS[@]}" "$NIX_USER@$server_ip" 'cat /etc/rancher/k3s/k3s.yaml' >"$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
export KUBECONFIG="$PWD/$KUBECONFIG_FILE"
kubectl config set-cluster default --server="https://$server_ip:6443"

echo "Waiting for ${#IPs[@]} nodes to join the cluster"
wait_until "all nodes to join" all_nodes_joined
kubectl wait --for=condition=Ready nodes --all --timeout="${WAIT_TIMEOUT}s"

# helmfile apply needs helm-diff, and helm-secrets for the sops encrypted values
helm plugin list | grep -q '^diff' || helm plugin install --verify=false https://github.com/databus23/helm-diff
helm plugin list | grep -q '^secrets' || helm plugin install --verify=false https://github.com/jkroepke/helm-secrets

helmfile -f helm/helmfile.yaml apply

kubectl get nodes
