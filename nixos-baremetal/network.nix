# Static LAN address of each node: meta.address is set per host in flake.nix, nodes lists them all.
{ lib, meta, nodes, ... }:

{
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    # physical ethernet only (enp*, eno*, ens*), not the cni/flannel/docker interfaces created by k3s
    matchConfig.Name = "en*";
    address = [ "${meta.address}/24" ];
    gateway = [ "192.168.1.254" ];
    dns = [ "192.168.1.254" ];
  };

  # k3s joins the cluster through https://homelab-0:6443, resolve the nodes without relying on DNS
  networking.hosts = lib.mapAttrs' (name: ip: lib.nameValuePair ip [ name ]) nodes;
}
