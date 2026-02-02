{ config, pkgs, ... }:

{
  # Install rclone
  environment.systemPackages = with pkgs; [
    rclone
  ];

  # rclone config is managed via sops-nix secrets
  # The config file will be placed at /run/secrets/rclone.conf
  # 
  # To use: rclone --config /run/secrets/rclone.conf <command>
  # Or set RCLONE_CONFIG=/run/secrets/rclone.conf
  #
  # The config should contain:
  # [storj]
  # type = s3
  # provider = Storj
  # access_key_id = <key>
  # secret_access_key = <secret>
  # endpoint = gateway.storjshare.io
  #
  # [storj-crypt]
  # type = crypt
  # remote = storj:backup
  # password = <obscured>
  # password2 = <obscured>
  # filename_encryption = standard
  # directory_name_encryption = true

  # For now, we'll use a simple approach:
  # The rclone config is placed in /root/.config/rclone/rclone.conf
  # This will be migrated to sops-nix later

  # Create rclone config directory
  systemd.tmpfiles.rules = [
    "d /root/.config/rclone 0700 root root -"
  ];
}
