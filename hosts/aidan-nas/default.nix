{ config, pkgs, inputs, ... }:

{
  imports = [
    ./disko.nix
    ./hardware.nix
    ./filesystems.nix
    ./networking.nix
    ./users.nix
    ../../modules/secrets.nix
    ../../modules/docker.nix
    ../../modules/samba.nix
    ../../modules/tailscale.nix
    ../../modules/rclone.nix
    ../../modules/glance.nix
    ../../modules/maintenance.nix
    # Reverse proxy & auth
    ../../modules/acme.nix
    ../../modules/caddy.nix
    ../../modules/authelia.nix
    ../../modules/adguardhome.nix
    # Upgrades & monitoring
    ../../modules/auto-upgrade.nix
    ../../modules/diun.nix
    # Media services
    ../../modules/jellyfin.nix
    ../../modules/sonarr.nix
    ../../modules/radarr.nix
    ../../modules/bazarr.nix
    ../../modules/kavita.nix
    ../../modules/immich.nix
    # Security & utilities
    ../../modules/vaultwarden.nix
    ../../modules/cloudflare-ddns.nix
    # OCI containers (no native NixOS module on 24.11)
    ../../modules/qbittorrent.nix
    ../../modules/stash.nix
    ../../modules/linkding.nix
    ../../modules/retrom.nix
  ];

  # System
  system.stateVersion = "24.11";
  nixpkgs.config.allowUnfree = true;

  # Nix settings (gc + auto-optimise-store in modules/maintenance.nix)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Boot
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    # Enable zswap, disable THP (better for Redis, Postgres, etc.)
    kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.zpool=z3fold"
      "transparent_hugepage=never"
    ];
    kernel.sysctl = {
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "vm.dirty_ratio" = 10;
      "vm.dirty_background_ratio" = 5;
    };
  };

  # Timezone & Locale
  time.timeZone = "Asia/Singapore";
  i18n.defaultLocale = "en_US.UTF-8";

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    btop
    ncdu
    tree
    curl
    wget
    jq
    rclone
    mergerfs
    smartmontools
  ];

  # SSD I/O scheduler: use 'none' for NVMe/SSD, 'mq-deadline' for HDD
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
  '';

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Firewall (managed by networking.nix)
  networking.firewall.enable = true;
}
