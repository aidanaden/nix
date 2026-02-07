{ config, pkgs, ... }:

{
  # Primary Radarr instance (movies)
  services.radarr = {
    enable = true;
    dataDir = "/config/radarr";
    openFirewall = true;
    group = "users";
  };

  # Wait for mergerfs
  systemd.services.radarr = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };

  # Secondary instance (mobile) as OCI container
  virtualisation.oci-containers.containers.radarr-mobile = {
    image = "lscr.io/linuxserver/radarr:latest";
    ports = [ "7879:7878" ];
    volumes = [
      "/config/radarr-mobile:/config"
      "/data/shared/media/movies-mobile:/movies-mobile"
      "/data/shared/media:/media"
    ];
    environment = {
      PUID = "1001";
      PGID = "100";
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=radarr-mobile"
      "--memory=256m"
    ];
  };

  systemd.services.docker-radarr-mobile = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
