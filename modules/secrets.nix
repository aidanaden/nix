{ config, ... }:

{
  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;

    # Age key location on the NAS (copied during nixos-anywhere deployment)
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets = {
      # Tailscale auth key for automatic authentication
      tailscale_auth_key = {
        # Decrypted to /run/secrets/tailscale_auth_key
      };

      # rclone config with storj + storj-crypt remotes
      rclone_conf = {
        path = "/root/.config/rclone/rclone.conf";
        owner = "root";
        group = "root";
        mode = "0600";
      };

      # Cloudflare API token for ACME DNS-01 challenge
      # Format: CLOUDFLARE_DNS_API_TOKEN=your_token_here
      cloudflare_env = {
        owner = "acme";
        group = "acme";
        mode = "0400";
      };

      # Authelia secrets (64+ character random strings)
      authelia_jwt_secret = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      authelia_storage_encryption_key = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      authelia_session_secret = {
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

      # Telegram bot for notifications (used by maintenance scripts + DIUN)
      telegram_bot_token = { };
      telegram_chat_id = { };

      # Kavita token key (512+ bit, base64-encoded)
      kavita_token_key = {
        owner = "kavita";
        mode = "0400";
      };

      # Vaultwarden environment file (contains ADMIN_TOKEN=...)
      vaultwarden_env = {
        owner = "vaultwarden";
        mode = "0400";
      };

      # Cloudflare API token for DDNS updates
      cloudflare_api_token = { };
    };

    # sops templates — generate env files from secrets at activation time
    # Used by containers that need secrets via --env-file
    templates."diun-env" = {
      content = ''
        DIUN_NOTIF_TELEGRAM_TOKEN=${config.sops.placeholder.telegram_bot_token}
        DIUN_NOTIF_TELEGRAM_CHATIDS=${config.sops.placeholder.telegram_chat_id}
      '';
    };
  };

  # Ensure the rclone config directory exists before sops places the file
  systemd.tmpfiles.rules = [
    "d /root/.config/rclone 0700 root root -"
  ];
}
