{ config, pkgs, ... }:

{
  # RetroM - retro game library manager (no NixOS module exists)
  virtualisation.oci-containers.containers.retrom = {
    image = "ghcr.io/jmberesford/retrom-service:latest";
    ports = [ "5101:5101" ];
    volumes = [
      "/data/shared/games/roms:/app/library"
      "/config/retrom:/app/config"
      "/data/shared/retrom:/app/data"
    ];
    environment = {
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=retrom"
      "--memory=512m"
    ];
  };

  # Wait for mergerfs
  systemd.services.docker-retrom = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
