{ config, pkgs, ... }:

{
  # Import the qbittorrent module from unstable
  # NOTE: services.qbittorrent is unstable-only (not in 24.11)
  # We use the OCI container approach for both instances since the
  # unstable module can't be trivially imported across nixpkgs versions.
  # When upgrading to 25.05+, switch primary to native services.qbittorrent.

  # Primary qBittorrent instance
  virtualisation.oci-containers.containers.qbittorrent = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    ports = [
      "8181:8181"
      "6881:6881"
      "6881:6881/udp"
    ];
    volumes = [
      "/config/qbittorrent:/config"
      "/data/shared/media:/media"
    ];
    environment = {
      PUID = "1001";
      PGID = "100";
      TZ = "Asia/Singapore";
      WEBUI_PORT = "8181";
    };
    extraOptions = [
      "--name=qbittorrent"
      "--memory=512m"
    ];
  };

  # Secondary qBittorrent instance
  virtualisation.oci-containers.containers.qbittorrent2 = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    ports = [
      "8182:8181"
      "6882:6881"
      "6882:6881/udp"
    ];
    volumes = [
      "/config/qbittorrent2:/config"
      "/data/shared/media:/media"
    ];
    environment = {
      PUID = "1001";
      PGID = "100";
      TZ = "Asia/Singapore";
      WEBUI_PORT = "8181";
    };
    extraOptions = [
      "--name=qbittorrent2"
      "--memory=384m"
    ];
  };

  # Wait for mergerfs
  systemd.services.docker-qbittorrent = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
  systemd.services.docker-qbittorrent2 = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
