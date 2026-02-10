{
  config,
  lib,
  ...
}: let
  mkToolContainer = name: cfg:
    {
      inherit (cfg) image;
      inherit (cfg) ports;
      extraOptions =
        [
          "--name=${name}"
          "--memory=${cfg.memory}"
        ]
        ++ (cfg.extraOptions or []);
    }
    // lib.optionalAttrs (cfg ? volumes) {inherit (cfg) volumes;}
    // lib.optionalAttrs (cfg ? environment) {inherit (cfg) environment;};

  tools = {
    stirling-pdf = {
      image = "frooodle/s-pdf:0.36.0";
      ports = ["9080:8080"];
      memory = "512m";
      environment = {
        TZ = config.time.timeZone;
        DOCKER_ENABLE_SECURITY = "false";
      };
    };

    cyberchef = {
      image = "ghcr.io/gchq/cyberchef:10.19.4";
      ports = ["8916:80"];
      memory = "256m";
    };

    squoosh = {
      image = "pnmcosta/squoosh:latest";
      ports = ["4411:8080"];
      memory = "256m";
    };

    convertx = {
      image = "ghcr.io/c4illin/convertx:v0.10.1";
      ports = ["3242:3000"];
      memory = "512m";
      volumes = ["/config/convertx:/app/data"];
      environment = {
        TZ = config.time.timeZone;
      };
    };

    vert = {
      image = "ghcr.io/cheeky-gorilla/vert:v5.2.2";
      ports = ["7214:3000"];
      memory = "256m";
    };

    reubah = {
      image = "ghcr.io/joshuaepstein/reubah:latest";
      ports = ["8088:8080"];
      memory = "256m";
    };

    it-tools = {
      image = "corentinth/it-tools:2024.10.22-7ca5933";
      ports = ["8020:80"];
      memory = "128m";
    };
  };
in {
  # Utility tools - OCI containers managed by Sablier (start/stop on demand)
  # These are lightweight tools that don't need to run 24/7
  virtualisation.oci-containers.containers =
    lib.mapAttrs mkToolContainer tools;
}
