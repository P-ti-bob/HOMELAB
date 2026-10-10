{ config, lib, pkgs, meta, ... }:

{
  imports = [];

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings.trusted-users = ["dyslexia"];
  };

  boot.loader.grub.enable = true;

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets."k3s-token" = {
    sopsFile = ./secrets/k3s-token.yaml;
    owner = "root";
    mode = "0400";
  };

  networking.hostName = meta.hostname;

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    keyMap = "us";
  };

  # Fixes for longhorn
  systemd.tmpfiles.rules = [
    "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
  ];
  virtualisation.docker.logDriver = "json-file";

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets."k3s-token".path;
    extraFlags = toString ([
	    "--write-kubeconfig-mode \"0644\""
	    "--disable servicelb"
	    "--disable traefik"
	    "--disable local-storage"
    ] ++ (if meta.hostname == "homelab-0" then [] else [
	      "--server https://homelab-0:6443"
    ]));
    clusterInit = (meta.hostname == "homelab-0");
  };

  services.openiscsi = {
    enable = true;
    name = "iqn.2016-04.com.open-iscsi:${meta.hostname}";
  };

  security.sudo.wheelNeedsPassword = false;
  users.users.dyslexia = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; 
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDULotEi1WrIjt0HlXFnCiCH0hfZWWhT4xSeU2uq9ddFJZAOJbQYiKJJ5YH2HSOx7CN1DhT/GBBhT/A3twbjrPnkj2o9RlMqPrST2/df95BzZugJOe4sJwWGPyJu9RiiIx77ZjWN3GonR2rcN97rhj4RPWSsQrLJm+4b6fzUroyXc7qODOycsgqeRwfikQE04//5Svi6xAkcVvqesKHFLgu4vJLN6e/+TBvUr9lZjoXSRRGbtTemtx29w2h1QshkuchibPcTj29NnAsiN/MOauAbTc7h0zdetyR0fEzB+sELqZNH+RayBhhxujgc7+Hj7ENIwhFBvdo21sMwBgYeYMXNhi6Huzpr0JYvVmW51J2+XCEW5tIYiVlXDlvHj87VILpoM2zMwvYIgOmbai5IwUM0PZ2nbKtNY/bo/0cyrEk5jpFJq7FZ4sQKFhqyIPP4L9rA9+FlcqVakjVZ3Hvl3a5Ad/zUadIE8hcStJ5JFiNgBn4jwWs+cdhCFFilznDnAV48olAKNKb/peBM7zW8Mkrn3kA7cjHdDkbjsxx5VRG69ls+e6wvkf7DgWktv69sYYcaE+ED22WWvfyznsxdAJHpwzNIQJuUG/KLsY32eOmmLNH6Oz3Pj6qOCu414Xq6p65BYTJDZiSAD59bf442CX3rbvZhjSGUNkZbHywS0YRbQ== whood@thinkpad"
    ];
  };

  environment.systemPackages = with pkgs; [
     vim
     k3s
     cifs-utils
     nfs-utils
     git
  ];

  services.openssh.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # ssh
      6443  # API k3s
      2379  # etcd clients
      2380  # etcd peers
      10250 # kubelet
      7946  # metallb memberlist
    ];
    allowedUDPPorts = [
      8472  # flannel vxlan
      7946  # metallb memberlist
    ];
    trustedInterfaces = [ "cni0" "flannel.1" ];
  };

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}
