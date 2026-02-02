{ config, pkgs, lib, ... }:

let
  glanceConfig = pkgs.writeText "glance.yml" ''
    server:
      port: 8080
      assets-path: /app/assets

    theme:
      background-color: 24 24 37
      primary-color: 137 180 250
      positive-color: 166 218 149
      negative-color: 243 139 168
      contrast-multiplier: 1.1

    pages:
      - name: Home
        columns:
          - size: small
            widgets:
              - type: clock
                hour-format: "24h"
                timezones:
                  - timezone: Asia/Singapore
                    label: Singapore

              - type: weather
                location: Singapore
                units: metric

              - type: bookmarks
                groups:
                  - title: Services
                    color: 137 180 250
                    links:
                      - title: Jellyfin
                        url: https://jellyfin.aidanaden.com
                      - title: Immich
                        url: https://photos.aidanaden.com
                      - title: Nextcloud
                        url: https://nextcloud.aidanaden.com
                      - title: Vaultwarden
                        url: https://vault.aidanaden.com
                  - title: Management
                    color: 249 226 175
                    links:
                      - title: Portainer
                        url: https://port.aidanaden.com
                      - title: Pi-hole
                        url: https://pihole.aidanaden.com
                      - title: Uptime Kuma
                        url: https://kuma.aidanaden.com
                  - title: Media
                    color: 166 218 149
                    links:
                      - title: Sonarr
                        url: https://sonarr.aidanaden.com
                      - title: Radarr
                        url: https://radarr.aidanaden.com
                      - title: Readarr
                        url: https://readarr.aidanaden.com
                      - title: qBittorrent
                        url: https://qb.aidanaden.com

          - size: full
            widgets:
              - type: monitor
                cache: 1m
                title: Services
                sites:
                  - title: Jellyfin
                    url: https://jellyfin.aidanaden.com
                    icon: si:jellyfin
                  - title: Immich
                    url: https://photos.aidanaden.com
                    icon: si:immich
                  - title: Nextcloud
                    url: https://nextcloud.aidanaden.com
                    icon: si:nextcloud
                  - title: Vaultwarden
                    url: https://vault.aidanaden.com
                    icon: si:bitwarden
                  - title: Pi-hole
                    url: https://pihole.aidanaden.com
                    icon: si:pihole

              - type: releases
                cache: 1h
                repositories:
                  - immich-app/immich
                  - jellyfin/jellyfin
                  - linuxserver/docker-sonarr
                  - linuxserver/docker-radarr
                  - nextcloud/server
                  - dani-garcia/vaultwarden

          - size: small
            widgets:
              - type: markets
                markets:
                  - symbol: BTC-USD
                    name: Bitcoin
                  - symbol: ETH-USD
                    name: Ethereum
                  - symbol: SOL-USD
                    name: Solana

              - type: reddit
                subreddit: selfhosted
                style: horizontal-cards
                limit: 5

              - type: reddit
                subreddit: homelab
                style: horizontal-cards
                limit: 5
  '';
in
{
  # Glance dashboard container
  # Run via Docker for simplicity (NixOS native service exists but Docker is easier)
  virtualisation.oci-containers.containers.glance = {
    image = "glanceapp/glance:latest";
    ports = [ "8080:8080" ];
    volumes = [
      "${glanceConfig}:/app/glance.yml:ro"
    ];
    extraOptions = [
      "--name=glance"
    ];
  };

  # Alternative: Use the NixOS glance service (if available in nixpkgs)
  # services.glance = {
  #   enable = true;
  #   settings = { ... };
  # };
}
