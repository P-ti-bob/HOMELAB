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

To set up a node from fresh, we use [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). This requires loading the nixos installer and then booting the node into it. It allow to remotely install nixos once the password is set on the nodes using the `passwd` command. 

The command we use is as follows:

```shell
nix run github:nix-community/nixos-anywhere \
--extra-experimental-features "nix-command flakes" \
-- --flake '.#homelab-0' nixos@192.168.1.100
```

make sure to replace with your own ip.

## helm

This directory is used to store the helm configuration of the node and is managed using [helmfile](https://github.com/helmfile/helmfile), which is a declarative spec for defining helm charts.

To install this on your cluster, you can simply use the following command.

```
helmfile apply
```


## kustomize

Kustomize allows you to manage multiple manifest files in a `Kustomize.yaml`, which also allows you to override values if you need to.

I don't use Kustomize that much in the video, but it's a tool I do often use and is available in `kubectl`.


## TODO
- [ ] update wifi and credentials
- [ ] create the iac structure
