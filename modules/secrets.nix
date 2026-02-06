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

      # Telegram bot for notifications (used by maintenance scripts)
      telegram_bot_token = { };
      telegram_chat_id = { };
    };
  };

  # Ensure the rclone config directory exists before sops places the file
  systemd.tmpfiles.rules = [
    "d /root/.config/rclone 0700 root root -"
  ];
}
