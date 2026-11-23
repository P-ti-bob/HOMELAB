# Homelab

This project is split into different directories depending on each service used.

## Requirements

To use this, you'll need the following installed on your sysetm

- nix
- kubectl
- helmfile
- helm
- git
- sops
- opentofu/terraform

## nixos

This directory contains the nixos configuration for setting
up each node with k3s.

The configuration makes use of nix flakes and is composed of 3 different instancies :

```
homelab-0
homelab-1
homelab-2
```

The nodes are KVM VMs on CloudStack (disk `/dev/vda`, legacy BIOS boot, IP via DHCP).
Nodes find each other by name (`homelab-0`, ...) through the CloudStack virtual router DNS,
so no IP is hardcoded in the nix configuration.

### Installation sequence

Run from the repository root. Install from scratch in this order:

**1. Create the VMs (Debian template) on CloudStack**

```bash
tofu -chdir=terraform init
tofu -chdir=terraform plan -out=.plan
tofu -chdir=terraform apply .plan
rm terraform/.plan   # the plan contains the decrypted CloudStack API keys, never commit it
tofu -chdir=terraform output vm_ips   # IPs in order: homelab-0, homelab-1, homelab-2
```

**2. Generate one SSH host key per VM and derive its age key**

sops-nix decrypts the secrets (`k3s-token`) with the machine's SSH host key.
New VMs get new host keys, so we generate them beforehand and inject them during installation.

```bash
for h in homelab-0 homelab-1 homelab-2; do
  mkdir -p hosts/$h/etc/ssh
  ssh-keygen -t ed25519 -N "" -C $h -f hosts/$h/etc/ssh/ssh_host_ed25519_key
  echo "$h: $(nix run nixpkgs#ssh-to-age < hosts/$h/etc/ssh/ssh_host_ed25519_key.pub)"
done
```

`hosts/` contains private keys: it is ignored by git and must never be committed.

**3. Re-encrypt the secrets for the new machines**

Replace the `&homelab0`, `&homelab1` and `&homelab2` keys in `.sops.yaml` with the age keys printed above, then:

```bash
sops updatekeys nixos/secrets/k3s-token.yaml
```

Commit `.sops.yaml` and `nixos/secrets/`.

**4. Install NixOS with nixos-anywhere**

The Debian template only accepts the `debian` user (passwordless sudo). nixos-anywhere kexecs
into a NixOS installer, so no ISO or `passwd` is needed. Install `homelab-0` first:
it initialises the cluster (`clusterInit`), and the other nodes join it at `https://homelab-0:6443`.

```bash
nix run github:nix-community/nixos-anywhere \
  --extra-experimental-features "nix-command flakes" \
  -- --flake './nixos#homelab-0' \
  --build-on remote \
  --extra-files hosts/homelab-0 \
  --target-host debian@<ip-homelab-0>
```

Then run the same command for `homelab-1` and `homelab-2`, changing the name, the `hosts/` directory and the IP.

`--build-on remote` makes the VM build its own system: the laptop only evaluates the flake and sends
the small `.drv` files, and the VM downloads the packages from `cache.nixos.org` with the CloudStack bandwidth.
For later config changes, do the same with `nixos-rebuild`:

```bash
nixos-rebuild switch --flake './nixos#homelab-0' \
  --build-host dyslexia@<ip-homelab-0> \
  --target-host dyslexia@<ip-homelab-0> --use-remote-sudo
```

**5. Verify access**

```bash
ssh dyslexia@<ip-homelab-0> kubectl get nodes
```

### Bare metal nodes

Physical nodes use their own flake, `nixos-baremetal/` (NVMe disk, UEFI/systemd-boot), which reuses
`nixos/configuration.nix`. `baremetal_setup.sh` runs steps 2 to 5 and the helm install on machines reachable over ssh
as `homelab-0`, `homelab-1` and `homelab-2` (DNS or `~/.ssh/config` alias). Set `INSTALL_USER` to the
user of the OS currently on the machines (root or passwordless sudo), or leave it empty to use the ssh config:

```bash
INSTALL_USER=root ./baremetal_setup.sh
```

- Nodes already on NixOS keep their SSH host key, the others get one from `hosts/baremetal/`.
  Their age keys go to the `&metalN` anchors of `.sops.yaml`.
- Before touching a node it checks that the disks of `nixos-baremetal/disko-config.nix` exist,
  and it asks before wiping a node that does not run NixOS.
- The installed nodes have a 128M ESP that fits about two kernels, so `configurationLimit = 2`.

## Remote access (Tailscale)

`nixos/tailscale.nix` installs Tailscale on every node (with Tailscale SSH).
`homelab-0` and `homelab-1` also advertise `192.168.1.0/24` (subnet routers, HA).

1. Create a reusable, tagged auth key in the Tailscale admin console and store it:
   ```bash
   sops nixos/secrets/tailscale-authkey.yaml   # replace REPLACE_ME
   ```
2. Deploy (`nixos-rebuild switch`, see above) on the 3 nodes.
3. In the admin console: approve the 2 advertised routes, and add a split DNS
   (domain of the lab -> `192.168.1.3`, the Pi-hole) so internal names resolve remotely.
4. If the remote network also uses `192.168.1.0/24`, the subnet route loses: reach the nodes with
   their `100.x` address / MagicDNS name (`ssh dyslexia@homelab-0`).

## helm

This directory is used to store the helm configuration of the node and is managed using helmfile, which is a declarative spec for defining helm charts.

To install this on your cluster, you can simply use the following command.

```bash
helmfile apply
```


## kustomize

Kustomize allows you to manage multiple manifest files in a `Kustomize.yaml`, which also allows you to override values if you need to.

I don't use Kustomize that much in the video, but it's a tool I do often use and is available in `kubectl`.


## CloudStack Cleaning :
To remove everything created on cloudstack by the script
```bash
tofu -chdir=terraform destroy
```


## TODO
- [x] remove wifi
- [x] create the iac structure (terraform/ on CloudStack)
