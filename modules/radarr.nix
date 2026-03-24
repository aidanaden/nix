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
  # Primary Radarr instance (movies)
  services.radarr = {
    enable = true;
    dataDir = "/config/radarr";
    openFirewall = false;
    group = "users";
    settings.server.bindaddress = "127.0.0.1";
  };

  # Wait for mergerfs
  systemd.services =
    {
      radarr = mergerfsDeps;
    }
    // dockerMergerfsServices ["radarr-mobile"];

  # Secondary instance (mobile) as OCI container
  virtualisation.oci-containers.containers.radarr-mobile = mkLinuxServerContainer {
    name = "radarr-mobile";
    image = "lscr.io/linuxserver/radarr:6.0.4.10291-ls295";
    ports = ["127.0.0.1:7879:7878"];
    volumes = [
      "/config/radarr-mobile:/config"
      "/data/shared/media/movies-mobile:/movies-mobile"
      "/data/shared/media:/media"
    ];
    memory = "256m";
  };
}
