{ config, pkgs, ... }:

let
  # Cloudflare DDNS update script using the API
  ddnsScript = pkgs.writeShellScriptBin "cloudflare-ddns" ''
    set -euo pipefail

    # Read API token from sops
    CF_TOKEN=$(cat ${config.sops.secrets.cloudflare_api_token.path})
    ZONE="aidanaden.com"
    SUBDOMAIN="vpn"
    FQDN="''${SUBDOMAIN}.''${ZONE}"

    # Get current public IP
    CURRENT_IP=$(${pkgs.curl}/bin/curl -s https://api.ipify.org)
    if [ -z "$CURRENT_IP" ]; then
      echo "ERROR: Could not determine public IP"
      exit 1
    fi

    # Get zone ID
    ZONE_ID=$(${pkgs.curl}/bin/curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones?name=''${ZONE}" \
      -H "Authorization: Bearer ''${CF_TOKEN}" \
      -H "Content-Type: application/json" | ${pkgs.jq}/bin/jq -r '.result[0].id')

    # Get record ID
    RECORD_ID=$(${pkgs.curl}/bin/curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/''${ZONE_ID}/dns_records?name=''${FQDN}&type=A" \
      -H "Authorization: Bearer ''${CF_TOKEN}" \
      -H "Content-Type: application/json" | ${pkgs.jq}/bin/jq -r '.result[0].id')

    # Get existing IP
    EXISTING_IP=$(${pkgs.curl}/bin/curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones/''${ZONE_ID}/dns_records/''${RECORD_ID}" \
      -H "Authorization: Bearer ''${CF_TOKEN}" \
      -H "Content-Type: application/json" | ${pkgs.jq}/bin/jq -r '.result.content')

    if [ "$CURRENT_IP" = "$EXISTING_IP" ]; then
      echo "IP unchanged: $CURRENT_IP"
      exit 0
    fi

    # Update record
    RESULT=$(${pkgs.curl}/bin/curl -s -X PUT \
      "https://api.cloudflare.com/client/v4/zones/''${ZONE_ID}/dns_records/''${RECORD_ID}" \
      -H "Authorization: Bearer ''${CF_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"A\",\"name\":\"''${FQDN}\",\"content\":\"''${CURRENT_IP}\",\"proxied\":false}")

    if echo "$RESULT" | ${pkgs.gnugrep}/bin/grep -q '"success":true'; then
      echo "Updated $FQDN: $EXISTING_IP -> $CURRENT_IP"
    else
      echo "ERROR: Failed to update DNS record"
      echo "$RESULT"
      exit 1
    fi
  '';
in
{
  # Cloudflare DDNS update timer
  systemd.services.cloudflare-ddns = {
    description = "Update Cloudflare DNS record";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ddnsScript}/bin/cloudflare-ddns";
    };
  };

  systemd.timers.cloudflare-ddns = {
    description = "Cloudflare DDNS update timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "30s";
    };
  };

  # Sops secret for Cloudflare API token
  sops.secrets.cloudflare_api_token = { };
}
