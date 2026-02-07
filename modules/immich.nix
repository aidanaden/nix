{ config, pkgs, ... }:

{
  services.immich = {
    enable = true;
    mediaLocation = "/data/shared/media/ncdata";
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;

    # Auto-configures PostgreSQL with pgvecto-rs + Redis
    database.enable = true;
    redis.enable = true;
    machine-learning.enable = true;

    environment = {
      TZ = "Asia/Singapore";
      # HDD storage type for optimal Postgres tuning
      DB_STORAGE_TYPE = "HDD";
    };
  };

  # Immich needs access to media files
  users.users.immich.extraGroups = [ "users" ];

  # Wait for mergerfs (media on data disks)
  systemd.services.immich-server = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
  systemd.services.immich-machine-learning = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
