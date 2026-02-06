{ config, pkgs, lib, ... }:

{
  # Redis for Authelia session storage
  services.redis.servers.authelia = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    settings = {
      maxmemory = "64mb";
      maxmemory-policy = "volatile-lru";
    };
  };

  # Authelia SSO
  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.sops.secrets.authelia_jwt_secret.path;
      storageEncryptionKeyFile = config.sops.secrets.authelia_storage_encryption_key.path;
      sessionSecretFile = config.sops.secrets.authelia_session_secret.path;
    };

    settings = {
      theme = "dark";
      default_2fa_method = "totp";

      server = {
        address = "tcp://127.0.0.1:9091/";
      };

      log = {
        level = "info";
        format = "text";
      };

      totp = {
        issuer = "aidanaden.com";
        period = 30;
        skew = 1;
      };

      webauthn = {
        disable = false;
        display_name = "Authelia";
        attestation_conveyance_preference = "indirect";
        user_verification = "preferred";
        timeout = "60s";
      };

      # File-based user authentication
      authentication_backend = {
        file = {
          path = "/config/authelia/users_database.yml";
          password = {
            algorithm = "argon2id";
            iterations = 3;
            memory = 65536;
            parallelism = 4;
            key_length = 32;
            salt_length = 16;
          };
        };
      };

      # Access control rules
      access_control = {
        default_policy = "deny";

        rules = [
          # Public services (have their own auth)
          {
            domain = [
              "vault.aidanaden.com"
              "jellyfin.aidanaden.com"
              "photos.aidanaden.com"
              "books.aidanaden.com"
              "linkding.aidanaden.com"
              "wg.aidanaden.com"
              "nextcloud.aidanaden.com"
              "nextcloud-aio.aidanaden.com"
              "owncast.aidanaden.com"
              "conduit.aidanaden.com"
              "frame.aidanaden.com"
            ];
            policy = "bypass";
          }
          # Protected services (require 2FA)
          {
            domain = [
              # Torrent clients
              "qb.aidanaden.com"
              "qb2.aidanaden.com"
              "transmission.aidanaden.com"
              # *arr stack
              "sonarr.aidanaden.com"
              "sonarr-mobile.aidanaden.com"
              "radarr.aidanaden.com"
              "radarr-mobile.aidanaden.com"
              "readarr.aidanaden.com"
              # Admin panels
              "port.aidanaden.com"
              "omv.aidanaden.com"
              "kuma.aidanaden.com"
              "retrom.aidanaden.com"
              "adguard.aidanaden.com"
              # Utility services (former sleepable)
              "pdf.aidanaden.com"
              "cyberchef.aidanaden.com"
              "squoosh.aidanaden.com"
              "convert.aidanaden.com"
              "vert.aidanaden.com"
              "image.aidanaden.com"
            ];
            policy = "two_factor";
          }
        ];
      };

      # Session configuration
      session = {
        name = "authelia_session";
        cookies = [
          {
            domain = "aidanaden.com";
            authelia_url = "https://auth.aidanaden.com";
            default_redirection_url = "https://auth.aidanaden.com";
          }
        ];
        expiration = "1h";
        inactivity = "5m";
        remember_me = "1M";

        redis = {
          host = "127.0.0.1";
          port = 6379;
        };
      };

      # Storage (SQLite)
      storage = {
        local = {
          path = "/var/lib/authelia-main/db.sqlite3";
        };
      };

      # Notifier (filesystem for now - can switch to SMTP later)
      notifier = {
        disable_startup_check = false;
        filesystem = {
          filename = "/var/lib/authelia-main/notification.txt";
        };
      };

      # Identity validation
      identity_validation = {
        reset_password = {
          jwt_lifespan = "5m";
          jwt_algorithm = "HS256";
        };
      };
    };
  };

  # Ensure authelia user can read the users database
  systemd.services.authelia-main = {
    serviceConfig = {
      # Allow reading user database from /config
      ReadOnlyPaths = [ "/config/authelia" ];
    };
  };

  # Ensure config directory exists
  systemd.tmpfiles.rules = [
    "d /config/authelia 0750 authelia-main authelia-main -"
  ];

  # sops-nix secrets for Authelia
  sops.secrets = {
    authelia_jwt_secret = {
      owner = "authelia-main";
      group = "authelia-main";
      mode = "0400";
    };
    authelia_storage_encryption_key = {
      owner = "authelia-main";
      group = "authelia-main";
      mode = "0400";
    };
    authelia_session_secret = {
      owner = "authelia-main";
      group = "authelia-main";
      mode = "0400";
    };
  };
}
