{ config, lib, meta, ... }:

let
  # homelab-0 and homelab-1 advertise the LAN (two routers = HA, homelab-2 stays a plain node)
  lanRouters = [ "homelab-0" "homelab-1" ];
  isRouter = builtins.elem meta.hostname lanRouters;
in
{
  sops.secrets."tailscale-authkey" = {
    sopsFile = ./secrets/tailscale-authkey.yaml;
    owner = "root";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    # enables ip forwarding (needed to route the LAN for remote clients)
    useRoutingFeatures = if isRouter then "server" else "client";
    authKeyFile = config.sops.secrets."tailscale-authkey".path;
    extraUpFlags = [
      "--ssh"
      "--hostname=${meta.hostname}"
    ] ++ lib.optional isRouter "--advertise-routes=192.168.1.0/24";
    # nodes keep their own LAN routes: never let a remote subnet route override them
    # nodes keep Pi-hole / the box as DNS: the tailnet DNS config must not rewrite their resolv.conf
    extraSetFlags = [ "--accept-routes=false" "--accept-dns=false" ];
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ]; # direct (non-relayed) WireGuard connections
    checkReversePath = "loose";  # required for subnet routing
  };
}
