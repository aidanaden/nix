{
  # Single source of truth for *.aidanaden.com service inventory.
  #
  # Keep this aligned with:
  # - modules/caddy.nix (routing + Sablier)
  # - modules/authelia.nix (access-control)
  #
  # This does not attempt to unify the OMV compose/* configs; those are separate.

  domain = "aidanaden.com";
  upstream = "127.0.0.1";

  services = {
    # Public services: "own auth" or otherwise bypass Authelia.
    public = {
      jellyfin = {port = 8096;};
      photos = {port = 2283;}; # Immich
      books = {port = 5000;}; # Kavita
      vault = {port = 8321;}; # Vaultwarden
      linkding = {port = 9697;};
      frame = {port = 3456;}; # Immich Frame
      syncthing = {port = 8384;};
      ntfy = {port = 2586;};
    };

    # Protected services: require Authelia forward_auth (2FA policy).
    protected = {
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

    # Sleepable services: Authelia forward_auth + Sablier on-demand start/stop.
    sleepable = {
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
  };
}
