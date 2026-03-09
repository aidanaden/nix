{pkgs, ...}: {
  imports = [
    ./disko.nix
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/auto-upgrade.nix
    ../../modules/syncthing.nix
    ../../modules/retrom.nix
    ../../modules/retro-lockd.nix
  ];

  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;
  hardware.enableRedistributableFirmware = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.fstrim.enable = true;
  system.autoUpgrade.enable = false;

  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    btop
    curl
    git
    htop
    jq
    ncdu
    smartmontools
    tree
    vim
    wget
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets.tailscale_auth_key = {};
  };

  services.tailscale.useRoutingFeatures = "client";
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  homelab.syncthing = {
    dataDir = "/data/retro/shared";
    configDir = "/var/lib/syncthing";
    guiAddress = "0.0.0.0:8384";
    openDefaultPorts = false;
    waitFor = [];
  };

  services.syncthing = {
    overrideDevices = false;
    overrideFolders = true;

    settings = {
      folders.retro = {
        id = "retro";
        label = "Retro";
        path = "/data/retro/shared";
        devices = [];
      };

      options = {
        globalAnnounceEnabled = false;
        localAnnounceEnabled = false;
        natEnabled = false;
        relaysEnabled = false;
      };
    };
  };

  homelab.retrom = {
    libraryPath = "/data/retro/shared/roms";
    configPath = "/var/lib/retro/config/retrom";
    dataPath = "/var/lib/retro/cache/retrom";
    waitFor = [];
  };

  systemd.services.retrom-tailscale-firewall = {
    description = "Restrict Retrom Docker port to Tailscale";
    wantedBy = ["multi-user.target"];
    after = ["docker.service" "firewall.service"];
    requires = ["docker.service"];
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
    };
    script = ''
      ${pkgs.iptables}/bin/iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 5101 -j ACCEPT 2>/dev/null || \
        ${pkgs.iptables}/bin/iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport 5101 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -C DOCKER-USER ! -i tailscale0 -p tcp --dport 5101 -j DROP 2>/dev/null || \
        ${pkgs.iptables}/bin/iptables -I DOCKER-USER 2 ! -i tailscale0 -p tcp --dport 5101 -j DROP
    '';
    preStop = ''
      ${pkgs.iptables}/bin/iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 5101 -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D DOCKER-USER ! -i tailscale0 -p tcp --dport 5101 -j DROP 2>/dev/null || true
    '';
  };

  homelab.retroLockd.enable = true;

  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /data/retro 0750 aidan users -"
    "d /data/retro/shared 0750 aidan users -"
    "d /data/retro/shared/artwork 0750 aidan users -"
    "d /data/retro/shared/metadata 0750 aidan users -"
    "d /data/retro/shared/roms 0750 aidan users -"
    "d /data/retro/shared/saves 0750 aidan users -"
    "d /data/retro/shared/states 0750 aidan users -"
    "d /var/lib/retro 0750 aidan users -"
    "d /var/lib/retro/cache 0750 aidan users -"
    "d /var/lib/retro/config 0750 aidan users -"
    "d /var/lib/retro/logs 0750 aidan users -"
  ];
}
