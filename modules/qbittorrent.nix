{
  config,
  lib,
  ...
}: let
  commonEnv = {
    PUID = "1001";
    PGID = "100";
    TZ = config.time.timeZone;
    WEBUI_PORT = "8181";
  };

  mergerfsDeps = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };

  instances = {
    qbittorrent = {
      webPort = 8181;
      torrentPort = 6881;
      memory = "512m";
    };
    qbittorrent2 = {
      webPort = 8182;
      torrentPort = 6882;
      memory = "384m";
    };
  };

  mkQbittorrentContainer = name: cfg: {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    ports = [
      "${toString cfg.webPort}:8181"
      "${toString cfg.torrentPort}:6881"
      "${toString cfg.torrentPort}:6881/udp"
    ];
    volumes = [
      "/config/${name}:/config"
      "/data/shared/media:/media"
    ];
    environment = commonEnv;
    extraOptions = [
      "--name=${name}"
      "--memory=${cfg.memory}"
    ];
  };

  dockerMergerfsServices = names:
    builtins.listToAttrs (map (name: {
        name = "docker-${name}";
        value = mergerfsDeps;
      })
      names);
in {
  # Import the qbittorrent module from unstable
  # NOTE: services.qbittorrent is unstable-only (not in 24.11)
  # We use the OCI container approach for both instances since the
  # unstable module can't be trivially imported across nixpkgs versions.
  # When upgrading to 25.05+, switch primary to native services.qbittorrent.

  virtualisation.oci-containers.containers =
    lib.mapAttrs mkQbittorrentContainer instances;

  # Wait for mergerfs
  systemd.services = dockerMergerfsServices (builtins.attrNames instances);
}
