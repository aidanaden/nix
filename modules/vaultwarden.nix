{ config, pkgs, ... }:

{
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    backupDir = "/var/backup/vaultwarden";

    # Configuration as environment variables
    config = {
      DOMAIN = "https://vault.aidanaden.com";
      SIGNUPS_ALLOWED = false;
      SENDS_ALLOWED = true;
      EMERGENCY_ACCESS_ALLOWED = true;
      WEB_VAULT_ENABLED = true;
      LOGIN_RATELIMIT_MAX_BURST = 10;
      LOGIN_RATELIMIT_SECONDS = 60;
      ADMIN_RATELIMIT_MAX_BURST = 10;
      ADMIN_RATELIMIT_SECONDS = 60;
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = 8321;
    };

    # ADMIN_TOKEN via sops (use argon2 hash)
    environmentFile = config.sops.secrets.vaultwarden_env.path;
  };

  # Sops secret for Vaultwarden admin token
  sops.secrets.vaultwarden_env = {
    owner = "vaultwarden";
    mode = "0400";
  };
}
