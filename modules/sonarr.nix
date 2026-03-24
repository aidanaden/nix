{config, ...}: let
  commonEnv = {
    PUID = "1001";
    PGID = "100";
    TZ = config.time.timeZone;
  };

  mergerfsDeps = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };

  mkLinuxServerContainer = {
    name,
    image,
    ports,
    volumes,
    memory,
    environment ? {},
  }: {
    inherit image ports volumes;
    environment = commonEnv // environment;
    extraOptions = [
      "--name=${name}"
      "--memory=${memory}"
    ];
  };

  dockerMergerfsServices = names:
    builtins.listToAttrs (map (name: {
        name = "docker-${name}";
        value = mergerfsDeps;
      })
      names);
in {
  # Primary Sonarr instance (TV series)
  services.sonarr = {
    enable = true;
    dataDir = "/config/sonarr";
    openFirewall = false;
    group = "users";
    settings.server.bindaddress = "127.0.0.1";
  };

  # Wait for mergerfs
  systemd.services =
    {
      sonarr = mergerfsDeps;
    }
    // dockerMergerfsServices ["sonarr-mobile"];

  # Secondary instance (mobile/anime) as OCI container
  virtualisation.oci-containers.containers.sonarr-mobile = mkLinuxServerContainer {
    name = "sonarr-mobile";
    image = "lscr.io/linuxserver/sonarr:4.0.17.2952-ls305";
    ports = ["127.0.0.1:8990:8989"];
    volumes = [
      "/config/sonarr-mobile:/config"
      "/data/shared/media/anime-mobile:/anime"
      "/data/shared/media/tv-mobile:/tv-mobile"
      "/data/shared/media:/media"
    ];
    memory = "512m";
  };
}
