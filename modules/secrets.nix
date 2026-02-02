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
    };
  };

  # Ensure the rclone config directory exists before sops places the file
  systemd.tmpfiles.rules = [
    "d /root/.config/rclone 0700 root root -"
  ];
}
