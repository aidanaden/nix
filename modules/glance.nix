{config, ...}: {
  services.glance = {
    enable = true;
    openFirewall = true;

    settings = {
      server = {
        port = 8080;
      };

      theme = {
        background-color = "24 24 37";
        primary-color = "137 180 250";
        positive-color = "166 218 149";
        negative-color = "243 139 168";
        contrast-multiplier = 1.1;
      };

      pages = [
        {
          name = "Home";
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "clock";
                  hour-format = "24h";
                  timezones = [
                    {
                      timezone = config.time.timeZone;
                      label = "Local";
                    }
                  ];
                }
                {
                  type = "weather";
                  location = "Singapore";
                  units = "metric";
                }
                {
                  type = "bookmarks";
                  groups = [
                    {
                      title = "Services";
                      color = "137 180 250";
                      links = [
                        {
                          title = "Jellyfin";
                          url = "https://jellyfin.aidanaden.com";
                        }
                        {
                          title = "Immich";
                          url = "https://photos.aidanaden.com";
                        }
                        {
                          title = "Vaultwarden";
                          url = "https://vault.aidanaden.com";
                        }
                        {
                          title = "Kavita";
                          url = "https://books.aidanaden.com";
                        }
                        {
                          title = "Linkding";
                          url = "https://linkding.aidanaden.com";
                        }
                        {
                          title = "Paperless";
                          url = "https://paperless.aidanaden.com";
                        }
                      ];
                    }
                    {
                      title = "Management";
                      color = "249 226 175";
                      links = [
                        {
                          title = "Portainer";
                          url = "https://port.aidanaden.com";
                        }
                        {
                          title = "AdGuard Home";
                          url = "https://adguard.aidanaden.com";
                        }
                        {
                          title = "Dozzle";
                          url = "https://dozzle.aidanaden.com";
                        }
                        {
                          title = "Netdata";
                          url = "https://netdata.aidanaden.com";
                        }
                        {
                          title = "Healthchecks";
                          url = "https://healthchecks.aidanaden.com";
                        }
                        {
                          title = "Syncthing";
                          url = "https://syncthing.aidanaden.com";
                        }
                      ];
                    }
                    {
                      title = "Media";
                      color = "166 218 149";
                      links = [
                        {
                          title = "Sonarr";
                          url = "https://sonarr.aidanaden.com";
                        }
                        {
                          title = "Radarr";
                          url = "https://radarr.aidanaden.com";
                        }
                        {
                          title = "Bazarr";
                          url = "https://bazarr.aidanaden.com";
                        }
                        {
                          title = "qBittorrent";
                          url = "https://qb.aidanaden.com";
                        }
                      ];
                    }
                    {
                      title = "Tools";
                      color = "203 166 247";
                      links = [
                        {
                          title = "IT-Tools";
                          url = "https://tools.aidanaden.com";
                        }
                        {
                          title = "Stirling PDF";
                          url = "https://pdf.aidanaden.com";
                        }
                        {
                          title = "CyberChef";
                          url = "https://cyberchef.aidanaden.com";
                        }
                        {
                          title = "Squoosh";
                          url = "https://squoosh.aidanaden.com";
                        }
                        {
                          title = "ConvertX";
                          url = "https://convert.aidanaden.com";
                        }
                        {
                          title = "Vert";
                          url = "https://vert.aidanaden.com";
                        }
                        {
                          title = "Reubah";
                          url = "https://image.aidanaden.com";
                        }
                      ];
                    }
                  ];
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "monitor";
                  cache = "1m";
                  title = "Services";
                  sites = [
                    {
                      title = "Jellyfin";
                      url = "https://jellyfin.aidanaden.com";
                      icon = "si:jellyfin";
                    }
                    {
                      title = "Immich";
                      url = "https://photos.aidanaden.com";
                      icon = "si:immich";
                    }
                    {
                      title = "Vaultwarden";
                      url = "https://vault.aidanaden.com";
                      icon = "si:bitwarden";
                    }
                    {
                      title = "AdGuard Home";
                      url = "https://adguard.aidanaden.com";
                      icon = "si:adguard";
                    }
                    {
                      title = "Syncthing";
                      url = "https://syncthing.aidanaden.com";
                      icon = "si:syncthing";
                    }
                    {
                      title = "Paperless";
                      url = "https://paperless.aidanaden.com";
                      icon = "si:paperlessngx";
                    }
                  ];
                }
                {
                  type = "releases";
                  cache = "1h";
                  repositories = [
                    "immich-app/immich"
                    "jellyfin/jellyfin"
                    "linuxserver/docker-sonarr"
                    "linuxserver/docker-radarr"
                    "dani-garcia/vaultwarden"
                    "glanceapp/glance"
                    "paperless-ngx/paperless-ngx"
                    "syncthing/syncthing"
                  ];
                }
              ];
            }
            {
              size = "small";
              widgets = [
                {
                  type = "markets";
                  markets = [
                    {
                      symbol = "BTC-USD";
                      name = "Bitcoin";
                    }
                    {
                      symbol = "ETH-USD";
                      name = "Ethereum";
                    }
                    {
                      symbol = "SOL-USD";
                      name = "Solana";
                    }
                  ];
                }
                {
                  type = "reddit";
                  subreddit = "selfhosted";
                  style = "horizontal-cards";
                  limit = 5;
                }
                {
                  type = "reddit";
                  subreddit = "homelab";
                  style = "horizontal-cards";
                  limit = 5;
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
