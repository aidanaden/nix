{ config, pkgs, ... }:

{
  # Healthchecks - cron job monitoring / dead man's switch
  # Monitors backup scripts, disk checks, and other scheduled tasks
  virtualisation.oci-containers.containers.healthchecks = {
    image = "healthchecks/healthchecks:v3.9";
    ports = [ "8011:8000" ];
    volumes = [
      "/config/healthchecks:/data"
    ];
    environment = {
      TZ = "Asia/Singapore";
      # Django settings
      ALLOWED_HOSTS = "healthchecks.aidanaden.com,localhost";
      SITE_ROOT = "https://healthchecks.aidanaden.com";
      SITE_NAME = "NAS Healthchecks";
      # Use SQLite (stored in /data)
      DB = "sqlite";
      DB_NAME = "/data/hc.sqlite";
      # Secret key (generate a random one)
      SECRET_KEY = "change-me-on-first-run";
      # Disable registration after initial setup
      REGISTRATION_OPEN = "False";
      # Ping settings
      PING_BODY_LIMIT = "10000";
    };
    extraOptions = [
      "--name=healthchecks"
      "--memory=256m"
    ];
  };

  # Wait for mergerfs
  systemd.services.docker-healthchecks = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };

  # Ensure config directory exists
  systemd.tmpfiles.rules = [
    "d /config/healthchecks 0750 root root -"
  ];
}
