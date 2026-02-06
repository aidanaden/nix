{ config, ... }:

{
  # ACME certificates via Cloudflare DNS-01 challenge
  # Generates wildcard cert for *.aidanaden.com
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "aidanaden@gmail.com";
      dnsProvider = "cloudflare";
      # sops-nix decrypts to /run/secrets/cloudflare_api_token
      # systemd EnvironmentFile expects: CLOUDFLARE_DNS_API_TOKEN=value
      environmentFile = config.sops.secrets.cloudflare_env.path;
    };

    certs."aidanaden.com" = {
      domain = "aidanaden.com";
      extraDomainNames = [ "*.aidanaden.com" ];
      # Allow caddy to read the certs
      group = "caddy";
    };
  };

  # Ensure caddy can read ACME certs
  users.users.caddy.extraGroups = [ "acme" ];

  # Secret for Cloudflare API token (as environment file format)
  sops.secrets.cloudflare_env = {
    # Format: CLOUDFLARE_DNS_API_TOKEN=your_token_here
    owner = "acme";
    group = "acme";
    mode = "0400";
  };
}
