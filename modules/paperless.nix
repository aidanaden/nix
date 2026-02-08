{ config, pkgs, ... }:

{
  # Paperless-ngx - document management with OCR
  # Scan/photograph documents, auto-categorize, full-text search
  virtualisation.oci-containers.containers.paperless = {
    image = "ghcr.io/paperless-ngx/paperless-ngx:2.14.7";
    ports = [ "8010:8000" ];
    volumes = [
      "/config/paperless:/usr/src/paperless/data"
      "/data/shared/paperless/media:/usr/src/paperless/media"
      "/data/shared/paperless/consume:/usr/src/paperless/consume"
      "/data/shared/paperless/export:/usr/src/paperless/export"
    ];
    environment = {
      TZ = "Asia/Singapore";
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_URL = "https://paperless.aidanaden.com";
      PAPERLESS_TIME_ZONE = "Asia/Singapore";
      PAPERLESS_TASK_WORKERS = "2";
      PAPERLESS_THREADS_PER_WORKER = "2";
      PAPERLESS_CONSUMER_RECURSIVE = "true";
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = "true";
      # Use built-in SQLite (no external Postgres needed)
      PAPERLESS_DBENGINE = "sqlite";
      # Tika + Gotenberg for Office document support (disabled to save resources)
      PAPERLESS_TIKA_ENABLED = "false";
      # Set UID/GID to match appuser
      USERMAP_UID = "1001";
      USERMAP_GID = "100";
    };
    extraOptions = [
      "--name=paperless"
      "--memory=1g"
    ];
  };

  # Wait for mergerfs (data on data disks)
  systemd.services.docker-paperless = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /config/paperless 0750 1001 100 -"
    "d /data/shared/paperless 0750 1001 100 -"
    "d /data/shared/paperless/media 0750 1001 100 -"
    "d /data/shared/paperless/consume 0750 1001 100 -"
    "d /data/shared/paperless/export 0750 1001 100 -"
  ];
}
