{
  config,
  lib,
  ...
}: let
  cfg = config.homelab.syncthing;
in {
  options.homelab.syncthing = {
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/data/shared/syncthing";
      description = "Syncthing data directory.";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/config/syncthing";
      description = "Syncthing config directory.";
    };

    guiAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:8384";
      description = "Syncthing GUI listen address.";
    };

    openDefaultPorts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open Syncthing sync and discovery ports in the firewall.";
    };

    waitFor = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["mergerfs.service"];
      description = "Additional services that Syncthing should wait for.";
    };

    extraTmpfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra tmpfiles rules for Syncthing-related paths.";
    };
  };

  config = {
    # Syncthing - P2P device sync (replaces Nextcloud for file sync)
    services.syncthing = {
      enable = true;
      user = "aidan";
      group = "users";
      inherit (cfg) dataDir;
      inherit (cfg) configDir;
      inherit (cfg) guiAddress;

      inherit (cfg) openDefaultPorts;

      settings = {
        gui = {
          address = cfg.guiAddress;
        };

        options = {
          urAccepted = lib.mkDefault (-1);
          relaysEnabled = lib.mkDefault true;
          localAnnounceEnabled = lib.mkDefault true;
          globalAnnounceEnabled = lib.mkDefault true;
        };
      };

      overrideFolders = lib.mkDefault false;
      overrideDevices = lib.mkDefault false;
    };

    systemd.services.syncthing = lib.mkIf (cfg.waitFor != []) {
      after = cfg.waitFor;
      requires = cfg.waitFor;
    };

    systemd.tmpfiles.rules =
      [
        "d ${cfg.dataDir} 0750 aidan users -"
        "d ${cfg.configDir} 0750 aidan users -"
      ]
      ++ cfg.extraTmpfiles;
  };
}
