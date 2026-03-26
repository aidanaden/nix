{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./disko.nix
    ./hardware.nix
    ./networking.nix
    ./users.nix
    ../../modules/docker.nix
    ../../modules/tailscale.nix
    ../../modules/auto-upgrade.nix
    ../../modules/home-automation.nix
    ../../modules/syncthing.nix
    ../../modules/retrom.nix
    ../../modules/retro-lockd.nix
  ];

  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;
  hardware.enableRedistributableFirmware = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.auto-optimise-store = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.fstrim.enable = true;
  services.chrony = {
    enable = true;
    servers = [
      "time.cloudflare.com"
      "time.google.com"
    ];
    extraConfig = ''
      allow 192.168.1.0/24
    '';
  };
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
    secrets = {
      tailscale_auth_key = {};
      amcrest_rtsp_user = {};
      amcrest_rtsp_password = {};
    };

    templates."amcrest-env" = {
      mode = "0400";
      content = ''
        FRIGATE_RTSP_USER=${config.sops.placeholder.amcrest_rtsp_user}
        FRIGATE_RTSP_PASSWORD=${config.sops.placeholder.amcrest_rtsp_password}
      '';
    };

    templates."homeassistant-amcrest-controls.yaml" = {
      mode = "0400";
      content = ''
        amcrest:
          - host: ${config.homelab.homeAutomation.camera.host}
            username: ${config.sops.placeholder.amcrest_rtsp_user}
            password: ${config.sops.placeholder.amcrest_rtsp_password}
            name: Studio Amcrest
            port: 80
            stream_source: snapshot
            binary_sensors:
              - online
            sensors:
              - ptz_preset
            switches:
              - privacy_mode
      '';
    };
  };

  services.tailscale.useRoutingFeatures = "client";
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
  };

  homelab.homeAutomation = {
    enable = true;

    homeAssistant = {
      amcrestPackageFile = config.sops.templates."homeassistant-amcrest-controls.yaml".path;
      mobileNotifyAction = "notify.mobile_app_youphone";
    };

    camera = {
      name = "studio";
      host = "192.168.1.6";
      credentialsFile = config.sops.templates."amcrest-env".path;
    };

    archive = {
      remoteHost = "aidan@100.92.143.10";
      remotePath = "/srv/mergerfs/data/security/catcam/review";
      sshKeyPath = "/var/lib/home-automation/secrets/nas_archive_ed25519";
    };
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
    listenAddress = "0.0.0.0";
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
