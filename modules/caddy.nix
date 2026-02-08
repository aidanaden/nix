{ config, pkgs, pkgs-unstable, lib, ... }:

let
  # Tailscale IP of the NAS (where Docker services run)
  upstream = "100.92.143.10";

  # Service definitions organized by auth type
  # Format: subdomain = { port = N; extraConfig = "..."; }

  # Services with their own auth - bypass Authelia
  publicServices = {
    # Media
    jellyfin = { port = 8096; };
    photos = { port = 2283; };  # Immich
    books = { port = 5000; };   # Kavita

    # Security
    vault = { port = 8321; };   # Vaultwarden

    # Other
    linkding = { port = 9697; };
    frame = { port = 3456; };    # Immich Frame

    # Sync
    syncthing = { port = 8384; };
  };

  # Services requiring Authelia 2FA
  protectedServices = {
    # Torrent clients
    qb = { port = 8181; };
    qb2 = { port = 8182; };
    transmission = { port = 9091; };

    # *arr stack
    sonarr = { port = 8989; };
    sonarr-mobile = { port = 8990; };
    radarr = { port = 7878; };
    radarr-mobile = { port = 7879; };
    bazarr = { port = 6767; };

    # Admin panels
    port = { port = 9000; };    # Portainer
    retrom = { port = 5101; };
    stash = { port = 9999; };

    # Monitoring & management
    dozzle = { port = 9010; };
    netdata = { port = 19999; };
    paperless = { port = 8010; };
    healthchecks = { port = 8011; };

    # AdGuard Home web UI
    adguard = { port = 3000; };
  };

  # Sleepable services (Sablier + Authelia)
  # These containers are stopped after inactivity and started on demand
  sleepableServices = {
    pdf = { port = 9080; container = "stirling-pdf"; displayName = "Stirling PDF"; };
    cyberchef = { port = 8916; container = "cyberchef"; displayName = "CyberChef"; };
    squoosh = { port = 4411; container = "squoosh"; displayName = "Squoosh"; };
    convert = { port = 3242; container = "convertx"; displayName = "ConvertX"; };
    vert = { port = 7214; container = "vert"; displayName = "Vert"; };
    image = { port = 8088; container = "reubah"; displayName = "Reubah"; };
    tools = { port = 8020; container = "it-tools"; displayName = "IT-Tools"; };
  };

  # Authelia forward_auth snippet
  autheliaForwardAuth = ''
    forward_auth localhost:9091 {
      uri /api/authz/forward-auth
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
    }
  '';

  # Generate virtual host config for a public service
  mkPublicHost = name: cfg: {
    name = "${name}.aidanaden.com";
    value = {
      useACMEHost = "aidanaden.com";
      extraConfig =
        if cfg ? extraConfig then cfg.extraConfig
        else "reverse_proxy ${upstream}:${toString cfg.port}";
    };
  };

  # Generate virtual host config for a protected service
  mkProtectedHost = name: cfg: {
    name = "${name}.aidanaden.com";
    value = {
      useACMEHost = "aidanaden.com";
      extraConfig = ''
        ${autheliaForwardAuth}
        ${if cfg ? extraConfig then cfg.extraConfig
          else "reverse_proxy ${upstream}:${toString cfg.port}"}
      '';
    };
  };

  # Generate virtual host config for a sleepable service (Sablier + Authelia)
  mkSleepableHost = name: cfg: {
    name = "${name}.aidanaden.com";
    value = {
      useACMEHost = "aidanaden.com";
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

in
{
  # Custom Caddy with Cloudflare DNS + Sablier plugins (requires unstable for withPlugins)
  services.caddy = {
    enable = true;
    package = pkgs-unstable.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.0.0-20240703190432-89f16b99c18e"
        "github.com/sablierapp/sablier-caddy-plugin@v1.8.0"
      ];
      hash = lib.fakeHash;
    };

    # Global options
    globalConfig = ''
      # Use ACME certs from security.acme module
      auto_https disable_certs

      # Sablier must be ordered before reverse_proxy
      order sablier before reverse_proxy
    '';

    virtualHosts = lib.mkMerge [
      # Authelia portal (no forward_auth on itself)
      {
        "auth.aidanaden.com" = {
          useACMEHost = "aidanaden.com";
          extraConfig = "reverse_proxy localhost:9091";
        };
      }

      # Ntfy (public push notifications - needs its own auth handling)
      {
        "ntfy.aidanaden.com" = {
          useACMEHost = "aidanaden.com";
          extraConfig = "reverse_proxy ${upstream}:2586";
        };
      }

      # Glance dashboard (protected)
      {
        "dash.aidanaden.com" = {
          useACMEHost = "aidanaden.com";
          extraConfig = ''
            ${autheliaForwardAuth}
            reverse_proxy localhost:8080
          '';
        };
      }

      # Public services (bypass Authelia)
      (builtins.listToAttrs (lib.mapAttrsToList mkPublicHost publicServices))

      # Protected services (require Authelia 2FA)
      (builtins.listToAttrs (lib.mapAttrsToList mkProtectedHost protectedServices))

      # Sleepable services (Sablier + Authelia 2FA)
      (builtins.listToAttrs (lib.mapAttrsToList mkSleepableHost sleepableServices))

      # Catch-all for undefined subdomains
      {
        "*.aidanaden.com" = {
          useACMEHost = "aidanaden.com";
          extraConfig = ''
            respond "Service not found" 404
          '';
        };
      }
    ];
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
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3 QUIC
}
