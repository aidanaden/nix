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
    # Enable zswap for memory compression
    kernelParams = [ "zswap.enabled=1" "zswap.compressor=zstd" "zswap.zpool=z3fold" ];
    # Disable THP (better for Redis, Postgres, etc.)
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
