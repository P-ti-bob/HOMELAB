{
  description = "Homelab NixOS Flake (physical nodes)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # sops-nix
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    # Disko
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Same nodes as ../nixos, only the hardware, disk layout, bootloader and network differ
  outputs = { self, nixpkgs, sops-nix, disko, ... }@inputs: let
    # hostname -> static LAN address (network.nix)
    nodes = {
      "homelab-0" = "192.168.1.10";
      "homelab-1" = "192.168.1.11";
      "homelab-2" = "192.168.1.12";
    };
  in {
    nixosConfigurations = nixpkgs.lib.mapAttrs (name: address: nixpkgs.lib.nixosSystem {
      specialArgs = {
        meta = { hostname = name; inherit address; };
        inherit nodes;
      };
      system = "x86_64-linux";
      modules = [
        # Modules
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
        ./hardware-configuration.nix
        ./disko-config.nix
        ./network.nix
        ../nixos/configuration.nix
      ];
    }) nodes;
  };
}
