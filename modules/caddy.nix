{
  pkgs-unstable,
  lib,
  ...
}: let
  domain = "aidanaden.com";
  upstream = "127.0.0.1";

  publicServices = {
    jellyfin = {port = 8096;};
    photos = {port = 2283;}; # Immich
    books = {port = 5000;}; # Kavita
    vault = {port = 8321;}; # Vaultwarden
    linkding = {port = 9697;};
    frame = {port = 3456;}; # Immich Frame
    syncthing = {port = 8384;};
    ntfy = {port = 2586;};
  };

  protectedServices = {
    qb = {port = 8181;};
    qb2 = {port = 8182;};
    sonarr = {port = 8989;};
    sonarr-mobile = {port = 8990;};
    radarr = {port = 7878;};
    radarr-mobile = {port = 7879;};
    bazarr = {port = 6767;};
    port = {port = 9000;};
    retrom = {port = 5101;};
    stash = {port = 9999;};
    dozzle = {port = 9010;};
    netdata = {port = 19999;};
    paperless = {port = 8010;};
    healthchecks = {port = 8011;};
    adguard = {port = 3000;};
    dash = {port = 8080;};
  };

  sleepableServices = {
    pdf = {
      port = 9080;
      container = "stirling-pdf";
      displayName = "Stirling PDF";
    };
    cyberchef = {
      port = 8916;
      container = "cyberchef";
      displayName = "CyberChef";
    };
    squoosh = {
      port = 4411;
      container = "squoosh";
      displayName = "Squoosh";
    };
    convert = {
      port = 3242;
      container = "convertx";
      displayName = "ConvertX";
    };
    vert = {
      port = 7214;
      container = "vert";
      displayName = "Vert";
    };
    image = {
      port = 8088;
      container = "reubah";
      displayName = "Reubah";
    };
    tools = {
      port = 8020;
      container = "it-tools";
      displayName = "IT-Tools";
    };
  };

  mkFqdn = name: "${name}.${domain}";

  # Authelia forward_auth snippet
  autheliaForwardAuth = ''
    forward_auth localhost:9091 {
      uri /api/authz/forward-auth
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
  '';

  # Generate virtual host config for a public service
  mkPublicHost = name: cfg: {
    name = mkFqdn name;
    value = {
      useACMEHost = domain;
      extraConfig =
        cfg.extraConfig or "reverse_proxy ${upstream}:${toString cfg.port}";
    };
  };

  # Generate virtual host config for a protected service
  mkProtectedHost = name: cfg: {
    name = mkFqdn name;
    value = {
      useACMEHost = domain;
      extraConfig = ''
        ${autheliaForwardAuth}
        ${
          cfg.extraConfig or "reverse_proxy ${upstream}:${toString cfg.port}"
        }
      '';
    };
  };

  # Generate virtual host config for a sleepable service (Sablier + Authelia)
  mkSleepableHost = name: cfg: {
    name = mkFqdn name;
    value = {
      useACMEHost = domain;
      extraConfig = ''
        ${autheliaForwardAuth}
        sablier {
          names ${cfg.container}
          session_duration 15m
          dynamic {
            display_name "${cfg.displayName}"
            theme hacker-terminal
          }
        }
        reverse_proxy ${upstream}:${toString cfg.port}
      '';
    };
  };

  staticHosts = {
    "auth.${domain}" = {
      useACMEHost = domain;
      extraConfig = "reverse_proxy ${upstream}:9091";
    };
  };

  publicHosts = builtins.listToAttrs (lib.mapAttrsToList mkPublicHost publicServices);
  protectedHosts = builtins.listToAttrs (lib.mapAttrsToList mkProtectedHost protectedServices);
  sleepableHosts = builtins.listToAttrs (lib.mapAttrsToList mkSleepableHost sleepableServices);

  catchAllHost = {
    "*.${domain}" = {
      useACMEHost = domain;
      extraConfig = ''
        respond "Service not found" 404
      '';
    };
  };
in {
  # Custom Caddy with Cloudflare DNS + Sablier plugins (requires unstable for withPlugins)
  services.caddy = {
    enable = true;
    package = pkgs-unstable.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.0.0-20240703190432-89f16b99c18e"
        "github.com/sablierapp/sablier-caddy-plugin@v1.0.1"
      ];
      # Source hash for the xcaddy build environment with the pinned plugins.
      hash = "sha256-oQWelgM4ygX3IjgrHg4V56bovTo1Dc9u25KS3t/5qgo=";
    };

    # Global options
    globalConfig = ''
      # Use ACME certs from security.acme module
      auto_https disable_certs

      # Sablier must be ordered before reverse_proxy
      order sablier before reverse_proxy
    '';

    virtualHosts = staticHosts // publicHosts // protectedHosts // sleepableHosts // catchAllHost;
  };

  # Sablier - on-demand container start/stop manager
  virtualisation.oci-containers.containers.sablier = {
    image = "sablierapp/sablier:1.11.1";
    extraOptions = [
      "--name=sablier"
      "--memory=64m"
    ];
    cmd = [
      "start"
      "--provider.name=docker"
    ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
  };

  # Open firewall for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [80 443];
  networking.firewall.allowedUDPPorts = [443]; # HTTP/3 QUIC
}
