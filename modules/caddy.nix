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
  };

  # Services requiring Authelia 2FA
  protectedServices = {
    # Torrent clients
    qb = { port = 8181; };
    qb2 = { port = 8182; };

    # *arr stack
    sonarr = { port = 8989; };
    sonarr-mobile = { port = 8990; };
    radarr = { port = 7878; };
    radarr-mobile = { port = 7879; };


    # Admin panels
    port = { port = 9000; };    # Portainer
    kuma = { port = 2468; };    # Uptime Kuma
    retrom = { port = 5101; };

    # Utility services
    pdf = { port = 9080; };       # Stirling PDF
    cyberchef = { port = 8916; };
    squoosh = { port = 4411; };
    convert = { port = 3242; };   # ConvertX

    # AdGuard Home web UI
    adguard = { port = 3000; };
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

in
{
  # Custom Caddy with Cloudflare DNS plugin (requires unstable for withPlugins)
  # Note: We use security.acme for certs, but still need the plugin for
  # on-demand TLS if ever needed
  services.caddy = {
    enable = true;
    package = pkgs-unstable.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.0.0-20240703190432-89f16b99c18e" ];
      hash = "sha256-EIxOAFDwwmCbLfzLNe+lxbHqBMZsVsg4P2YwuMwpclk=";
    };

    # Global options
    globalConfig = ''
      # Use ACME certs from security.acme module
      auto_https disable_certs
    '';

    virtualHosts = lib.mkMerge [
      # Authelia portal (no forward_auth on itself)
      {
        "auth.aidanaden.com" = {
          useACMEHost = "aidanaden.com";
          extraConfig = "reverse_proxy localhost:9091";
        };
      }

      # Public services (bypass Authelia)
      (builtins.listToAttrs (lib.mapAttrsToList mkPublicHost publicServices))

      # Protected services (require Authelia 2FA)
      (builtins.listToAttrs (lib.mapAttrsToList mkProtectedHost protectedServices))

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

  # Open firewall for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3 QUIC
}
