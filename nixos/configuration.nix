# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, meta, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
    ];

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    settings.trusted-users = ["dyslexia"];
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # sops-nix
  sops.defaultSopsFile = ./secrets/wifi.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets."wpa-psk" = {
    owner = "root";
    mode = "0400";
  };

  sops.secrets."k3s-token" = {
    sopsFile = ./secrets/k3s-token.yaml;
    owner = "root";
    mode = "0400";
  };

  # Renders WIFI_PSK=<decrypted value> to an env file NetworkManager can
  # source, so the psk never lands in the Nix store or configuration.nix.
  sops.templates."wifi-env".content = ''
    WIFI_PSK=${config.sops.placeholder."wpa-psk"}
  '';

  networking.hostName = meta.hostname; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";  # tells NM to use iwd, not wpa_supplicant

  networking.networkmanager.ensureProfiles.environmentFiles = [
    config.sops.templates."wifi-env".path
  ];

  networking.networkmanager.ensureProfiles.profiles = {
    "783F" = {
      connection = {
        id = "783F";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "783F";
        hidden = true;
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_PSK";
     };
    };
  };

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Fixes for longhorn
  systemd.tmpfiles.rules = [
    "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
  ];
  virtualisation.docker.logDriver = "json-file";

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";
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

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  security.sudo.wheelNeedsPassword = false;
  users.users.dyslexia = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
    # hashedPassword removed from history - set locally, not committed.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDULotEi1WrIjt0HlXFnCiCH0hfZWWhT4xSeU2uq9ddFJZAOJbQYiKJJ5YH2HSOx7CN1DhT/GBBhT/A3twbjrPnkj2o9RlMqPrST2/df95BzZugJOe4sJwWGPyJu9RiiIx77ZjWN3GonR2rcN97rhj4RPWSsQrLJm+4b6fzUroyXc7qODOycsgqeRwfikQE04//5Svi6xAkcVvqesKHFLgu4vJLN6e/+TBvUr9lZjoXSRRGbtTemtx29w2h1QshkuchibPcTj29NnAsiN/MOauAbTc7h0zdetyR0fEzB+sELqZNH+RayBhhxujgc7+Hj7ENIwhFBvdo21sMwBgYeYMXNhi6Huzpr0JYvVmW51J2+XCEW5tIYiVlXDlvHj87VILpoM2zMwvYIgOmbai5IwUM0PZ2nbKtNY/bo/0cyrEk5jpFJq7FZ4sQKFhqyIPP4L9rA9+FlcqVakjVZ3Hvl3a5Ad/zUadIE8hcStJ5JFiNgBn4jwWs+cdhCFFilznDnAV48olAKNKb/peBM7zW8Mkrn3kA7cjHdDkbjsxx5VRG69ls+e6wvkf7DgWktv69sYYcaE+ED22WWvfyznsxdAJHpwzNIQJuUG/KLsY32eOmmLNH6Oz3Pj6qOCu414Xq6p65BYTJDZiSAD59bf442CX3rbvZhjSGUNkZbHywS0YRbQ== whood@thinkpad"
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     neovim
     k3s
     cifs-utils
     nfs-utils
     git
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 80 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

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
  system.stateVersion = "23.11"; # Did you read the comment?

}
