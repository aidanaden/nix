{config, ...}: let
  catalog = import ./service-catalog.nix;
  inherit (catalog) domain;
  redisCfg = config.services.redis.servers.authelia;

  publicSubdomains = (builtins.attrNames catalog.services.public) ++ ["auth"];

  protectedSubdomains =
    (builtins.attrNames catalog.services.protected)
    ++ (builtins.attrNames catalog.services.sleepable);

  mkFqdn = name: "${name}.${domain}";
  publicDomains = builtins.map mkFqdn publicSubdomains;
  protectedDomains = builtins.map mkFqdn protectedSubdomains;
in {
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
          {
            domain = publicDomains;
            policy = "bypass";
          }
          {
            domain = protectedDomains;
            policy = "two_factor";
          }
        ];
      };

      # Session configuration
      session = {
        name = "authelia_session";
        cookies = [
          {
            inherit domain;
            authelia_url = "https://auth.${domain}";
            default_redirection_url = "https://auth.${domain}";
          }
        ];
        expiration = "1h";
        inactivity = "5m";
        remember_me = "1M";

        redis = {
          host = redisCfg.bind;
          inherit (redisCfg) port;
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

  # Ensure authelia starts after mergerfs (user DB lives on /config/authelia)
  systemd.services.authelia-main = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
    serviceConfig = {
      # Allow reading user database from /config
      ReadOnlyPaths = ["/config/authelia"];
    };
  };

  # Ensure config directory exists
  systemd.tmpfiles.rules = [
    "d /config/authelia 0750 authelia-main authelia-main -"
  ];

  # Note: Authelia secrets (authelia_jwt_secret, authelia_storage_encryption_key,
  # authelia_session_secret) are defined in modules/secrets.nix
}
