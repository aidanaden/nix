{ config, pkgs, ... }:

{
  # Primary Sonarr instance (TV series)
  services.sonarr = {
    enable = true;
    dataDir = "/config/sonarr";
    openFirewall = true;
    group = "users";
  };

  # Wait for mergerfs
  systemd.services.sonarr = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };

  # Secondary instance (mobile/anime) as OCI container
  virtualisation.oci-containers.containers.sonarr-mobile = {
    image = "lscr.io/linuxserver/sonarr:latest";
    ports = [ "8990:8989" ];
    volumes = [
      "/config/sonarr-mobile:/config"
      "/data/shared/media/anime-mobile:/anime"
      "/data/shared/media/tv-mobile:/tv-mobile"
      "/data/shared/media:/media"
    ];
    environment = {
      PUID = "1001";
      PGID = "100";
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=sonarr-mobile"
      "--memory=512m"
    ];
  };

  systemd.services.docker-sonarr-mobile = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
