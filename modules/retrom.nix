{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.retrom;
in {
  options.homelab.retrom = {
    libraryPath = lib.mkOption {
      type = lib.types.str;
      default = "/data/shared/games/roms";
      description = "Path to the RetroM ROM library.";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "/config/retrom";
      description = "Path to the RetroM config directory.";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/data/shared/retrom";
      description = "Path to the RetroM data directory.";
    };

    waitFor = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["mergerfs.service"];
      description = "Additional services that RetroM should wait for.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "RetroM listen address for Docker port publishing.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5101;
      description = "RetroM listen port.";
    };
  };

  config = {
    # RetroM - retro game library manager (no NixOS module exists)
    virtualisation.oci-containers.containers.retrom = {
      image = "ghcr.io/jmberesford/retrom-service:v0.8.0@sha256:42c37204270aeead444ae3643f39b412bd156b43710f50a3dca37d2b952bbadf";
      ports = ["${cfg.listenAddress}:${toString cfg.port}:5101"];
      volumes = [
        "${cfg.libraryPath}:/app/library"
        "${cfg.configPath}:/app/config"
        "${cfg.dataPath}:/app/data"
      ];
      environment = {
        COREPACK_HOME = "/app/data/corepack";
        XDG_CACHE_HOME = "/app/data/cache";
        TZ = config.time.timeZone;
      };
      extraOptions = [
        "--name=retrom"
        "--memory=512m"
      ];
    };

    systemd.services.docker-retrom = lib.mkIf (cfg.waitFor != []) {
      after = cfg.waitFor;
      requires = cfg.waitFor;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0750 aidan users -"
      "d ${cfg.dataPath} 0750 aidan users -"
      "d ${cfg.dataPath}/cache 0750 aidan users -"
      "d ${cfg.dataPath}/corepack 0750 aidan users -"
      "d ${cfg.dataPath}/db 0750 aidan users -"
      "d ${cfg.dataPath}/public 0750 aidan users -"
    ];
  };
}
