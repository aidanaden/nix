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

  # Note: cloudflare_env secret is defined in modules/secrets.nix
}
