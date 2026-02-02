{ config, pkgs, ... }:

{
  # Install rclone
  environment.systemPackages = with pkgs; [
    rclone
  ];

  # rclone config is managed via sops-nix secrets (see secrets.nix)
  # The config file is placed at /root/.config/rclone/rclone.conf
  # 
  # Available remotes:
  # - storj: Direct S3 access to Storj
  # - storj-crypt: Client-side encrypted access to storj:backup
  #
  # Usage:
  #   rclone ls storj-crypt:
  #   rclone copy /path/to/backup storj-crypt:vaultwarden/
}
