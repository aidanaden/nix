{ config, pkgs, lib, ... }:

{
  # AdGuard Home - DNS filtering and ad blocking
  services.adguardhome = {
    enable = true;

    # Allow UI-based changes to persist (password, clients, rewrites, etc.)
    # Initial settings below are applied on first boot only
    mutableSettings = true;

    # Open DNS ports
    openFirewall = true;

    settings = {
      # Web UI settings
      http = {
        address = "0.0.0.0:3000";
      };

      # Users - initial admin account (change password via UI after first boot)
      # With mutableSettings=true, UI changes persist across restarts
      # Generate new hash: htpasswd -nbB admin 'yourpassword' | cut -d: -f2
      users = [
        {
          name = "admin";
          # Placeholder - MUST change via AdGuard Home UI on first boot
          password = "$2y$10$hFGor5IZ9FQwnBbY5DFmYu3RqYQF1cNsNCQNjKVhFmKm/nHr2LPXC";
        }
      ];

      # DNS server settings
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;

        # Upstream DNS servers (Cloudflare DoH)
        upstream_dns = [
          "https://cloudflare-dns.com/dns-query"
          "https://dns.google/dns-query"
        ];

        # Bootstrap DNS (for resolving upstream hostnames)
        bootstrap_dns = [
          "1.1.1.1"
          "8.8.8.8"
        ];

        # Fallback DNS
        fallback_dns = [
          "1.0.0.1"
          "8.8.4.4"
        ];

        # Enable DNS-over-HTTPS for clients
        # Accessible at https://adguard.aidanaden.com/dns-query
        # (Caddy handles TLS termination)

        # Query logging
        querylog_enabled = true;
        querylog_file_enabled = true;
        querylog_interval = "24h";
        querylog_size_memory = 1000;

        # Cache settings
        cache_size = 4194304; # 4MB
        cache_ttl_min = 300;  # 5 minutes
        cache_ttl_max = 86400; # 24 hours

        # DNSSEC
        enable_dnssec = true;

        # Block settings
        blocking_mode = "default"; # Return 0.0.0.0 for blocked domains
        blocked_response_ttl = 10;

        # Rate limiting
        ratelimit = 100; # queries per second per client
        ratelimit_whitelist = [
          "127.0.0.1"
          "192.168.0.0/24"
          "100.64.0.0/10" # Tailscale
        ];
      };

      # Filtering settings
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;

        # Parental control (disabled by default)
        parental_enabled = false;

        # Safe browsing
        safe_browsing_enabled = true;

        # Safe search (force safe search on search engines)
        safe_search = {
          enabled = false; # Enable if needed
        };

        # Blocked services (empty = none blocked)
        blocked_services = {
          schedule = {
            time_zone = "Asia/Singapore";
          };
          ids = [ ]; # e.g., ["facebook", "tiktok", "instagram"]
        };

        # Update filters interval (in hours)
        filters_update_interval = 24;

        rewrites = [
          # Route all *.aidanaden.com to NAS Tailscale IP
          { domain = "*.aidanaden.com"; answer = "100.92.143.10"; }
          { domain = "aidanaden.com"; answer = "100.92.143.10"; }
        ];
      };

      # Filter lists
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          name = "AdAway Default Blocklist";
          id = 2;
        }
        {
          enabled = true;
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          name = "StevenBlack Unified";
          id = 3;
        }
        {
          enabled = true;
          url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
          name = "HaGeZi Pro";
          id = 4;
        }
      ];

      # Statistics
      statistics = {
        enabled = true;
        interval = "24h";
      };

      # Schema version
      schema_version = 29;
    };
  };

  # Ensure AdGuard Home starts after network is up
  systemd.services.adguardhome = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
