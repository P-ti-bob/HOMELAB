#!/usr/bin/env bash
set -euox pipefail

###################################################
##### My Automated Homelab setup (bare metal) #####
###################################################
# Same as cloudstack_setup.sh without the terraform part: the nodes are physical
# machines already reachable through ssh as homelab-0, homelab-1 and homelab-2
# (DNS or ~/.ssh/config alias). Uses the ./nixos-baremetal flake.
#
# INSTALL_USER: user of the OS currently on the nodes, needs root or passwordless sudo.
#               Leave empty to use the user from ~/.ssh/config.
#
# -f, --force-reinstall: wipe and reinstall NixOS on ALL nodes, ignoring what is already there
#                        (new SSH host keys, new age keys, disks repartitioned by disko).
#                        Each node still asks for confirmation before its disks are wiped.

cd "$(dirname "$0")"

FORCE_REINSTALL=false
while (($#)); do
  case "$1" in
    -f | --force-reinstall) FORCE_REINSTALL=true ;;
    -h | --help)
      echo "Usage: $0 [-f|--force-reinstall]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)
NIX_USER=dyslexia
INSTALL_USER="${INSTALL_USER:-}"
# nodes running NixOS only have NIX_USER: the ssh config user (often not present there) is not used for the reinstall
if $FORCE_REINSTALL; then INSTALL_USER="${INSTALL_USER:-$NIX_USER}"; fi
FLAKE=./nixos-baremetal
HOSTS=(homelab-0 homelab-1 homelab-2)        # homelab-0 must stay first, it is the k3s clusterInit server
WAIT_TIMEOUT=300                             # seconds to wait for SSH, k3s and nodes
HOSTS_DIR=hosts/baremetal                    # hosts/ is gitignored, it contains the SSH host private keys
KUBECONFIG_FILE=$HOSTS_DIR/kubeconfig        # cluster admin credentials

for cmd in jq nix sops nc ssh getent kubectl helm helmfile; do
  command -v "$cmd" >/dev/null || {
    echo "Missing required command: $cmd" >&2
    exit 1
  }
done

# resolve each host through ssh so ~/.ssh/config aliases work for nc and kubectl too
declare -A ADDR PORT IS_NIXOS
for host in "${HOSTS[@]}"; do
  ADDR[$host]="$(ssh -G "$host" | awk '$1 == "hostname" {print $2}')"
  PORT[$host]="$(ssh -G "$host" | awk '$1 == "port" {print $2}')"
  getent hosts "${ADDR[$host]}" >/dev/null || {
    echo "Cannot resolve $host (${ADDR[$host]}), add it to your DNS or ~/.ssh/config" >&2
    exit 1
  }
done

install_target() {
  echo "${INSTALL_USER:+$INSTALL_USER@}$1"
}

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
  wait_until "SSH on $1" nc -z -w 2 "${ADDR[$1]}" "${PORT[$1]}"
}

is_nixos() {
  ssh "${SSH_OPTS[@]}" "$NIX_USER@$1" 'test -e /etc/NIXOS' 2>/dev/null
}

for host in "${HOSTS[@]}"; do
  echo "Waiting for SSH on $host (${ADDR[$host]})"
  wait_for_ssh "$host"
  # --force-reinstall ignores the current OS of every node and treats it as a fresh install
  if ! $FORCE_REINSTALL && is_nixos "$host"; then IS_NIXOS[$host]=true; else IS_NIXOS[$host]=false; fi
done

if $FORCE_REINSTALL; then
  echo "--force-reinstall: ${HOSTS[*]} will be wiped and reinstalled, all data on their disks is lost" >&2
fi

#############################
##### Age keys creation #####
#############################
# Nodes already on NixOS keep their SSH host key, the others get a new one injected at install.
# The age keys go to the &metalN anchors of .sops.yaml (&homelabN are the CloudStack VMs).
keys_changed=false
for h in "${!HOSTS[@]}"; do
  host="${HOSTS[$h]}"
  key_file="$HOSTS_DIR/$host/etc/ssh/ssh_host_ed25519_key"

  if ${IS_NIXOS[$host]}; then
    pub_key="$(ssh "${SSH_OPTS[@]}" "$NIX_USER@$host" 'cat /etc/ssh/ssh_host_ed25519_key.pub')"
  else
    # a forced reinstall must not reuse the host key of the previous system
    $FORCE_REINSTALL && rm -f "$key_file" "$key_file.pub"
    mkdir -p "$HOSTS_DIR/$host/etc/ssh"
    [ -f "$key_file" ] || ssh-keygen -q -t ed25519 -N "" -C "$host" -f "$key_file"
    pub_key="$(cat "$key_file.pub")"
  fi
  age_key="$(nix run nixpkgs#ssh-to-age <<<"$pub_key")"

  if ! grep -Eq "^  - &metal$h +$age_key" .sops.yaml; then
    echo "$host: new age key $age_key"
    sed -i -E "s|^(  - &metal$h +)age1[a-z0-9]+|\1$age_key|" .sops.yaml
    grep -Eq "^  - &metal$h +$age_key" .sops.yaml || {
      echo "Failed to update &metal$h in .sops.yaml" >&2
      exit 1
    }
    keys_changed=true
  fi
done

# re-encrypt secrets so the hosts can decrypt them
if $keys_changed; then
  for f in nixos/secrets/*.yaml; do
    sops updatekeys -y "$f"
  done
fi

#########################
##### NixOS install #####
#########################
# disko and the bootloader expect the disks of nixos-baremetal/disko-config.nix: make sure they exist
check_disks() {
  local host=$1 target=$2 dev
  for dev in $(nix eval --extra-experimental-features "nix-command flakes" --json \
    "$FLAKE#nixosConfigurations.$host.config.disko.devices.disk" \
    --apply 'disks: map (d: d.device) (builtins.attrValues disks)' | jq -r '.[]'); do
    ssh "${SSH_OPTS[@]}" "$target" "test -b $dev" || {
      echo "$host has no $dev, fix nixos-baremetal/disko-config.nix and hardware-configuration.nix for this hardware" >&2
      return 1
    }
  done
}

for host in "${HOSTS[@]}"; do
  if ${IS_NIXOS[$host]}; then
    check_disks "$host" "$NIX_USER@$host"
    echo "$host already runs NixOS, skipping install"
    # apply config changes instead of reinstalling, built on the node itself
    NIX_SSHOPTS="${SSH_OPTS[*]}" nix run nixpkgs#nixos-rebuild \
      --extra-experimental-features "nix-command flakes" \
      -- switch --flake "$FLAKE#$host" \
      --build-host "$NIX_USER@$host" \
      --target-host "$NIX_USER@$host" --use-remote-sudo
  else
    check_disks "$host" "$(install_target "$host")"
    # physical disks: a failed is_nixos ssh check must not silently wipe a node
    read -rp "$host does not run NixOS, wipe its disks and install NixOS? [y/N] " answer
    [ "$answer" = y ] || exit 1
    echo "Installing NixOS on $host"
    # --build-on remote: the kexec installer builds the system and downloads packages itself
    nix run github:nix-community/nixos-anywhere \
      --extra-experimental-features "nix-command flakes" \
      -- --flake "$FLAKE#$host" \
      --build-on remote \
      --extra-files "$HOSTS_DIR/$host" \
      --target-host "$(install_target "$host")"
  fi
done

###############################
##### Helm charts install #####
###############################
server="${HOSTS[0]}"

kubeconfig_ready() {
  ssh "${SSH_OPTS[@]}" "$NIX_USER@$server" 'test -s /etc/rancher/k3s/k3s.yaml'
}

all_nodes_joined() {
  [ "$(kubectl get nodes --no-headers | wc -l)" -ge "${#HOSTS[@]}" ]
}

echo "Waiting for k3s on $server (${ADDR[$server]})"
wait_for_ssh "$server"
wait_until "k3s kubeconfig on $server" kubeconfig_ready

# k3s always writes 127.0.0.1 in its kubeconfig, point it to homelab-0
mkdir -p "$HOSTS_DIR"
ssh "${SSH_OPTS[@]}" "$NIX_USER@$server" 'cat /etc/rancher/k3s/k3s.yaml' >"$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"
export KUBECONFIG="$PWD/$KUBECONFIG_FILE"
kubectl config set-cluster default --server="https://${ADDR[$server]}:6443"

echo "Waiting for ${#HOSTS[@]} nodes to join the cluster"
wait_until "all nodes to join" all_nodes_joined
kubectl wait --for=condition=Ready nodes --all --timeout="${WAIT_TIMEOUT}s"

# helmfile apply needs helm-diff, and helm-secrets for the sops encrypted values
helm plugin list | grep -q '^diff' || helm plugin install --verify=false https://github.com/databus23/helm-diff
helm plugin list | grep -q '^secrets' || helm plugin install --verify=false https://github.com/jkroepke/helm-secrets

helmfile -f helm/helmfile.yaml apply

###############################
##### Kustomize manifests #####
###############################
# MetalLB IPAddressPool + L2Advertisement (no pool = every LoadBalancer service stays <pending>) and the headlamp token.
# helmfile does not wait for its releases: retry until the MetalLB webhook (served by its controller) accepts them.
echo "Applying kustomize/ (MetalLB IP pool, headlamp token)"
wait_until "the MetalLB webhook to accept kustomize/" kubectl apply -k kustomize/

kubectl get nodes
