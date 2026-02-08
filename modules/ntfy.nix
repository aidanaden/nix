{ config, pkgs, ... }:

{
  # Ntfy - push notification service
  # Used for sending alerts from backup scripts, healthchecks, etc.
  virtualisation.oci-containers.containers.ntfy = {
    image = "binwiederhier/ntfy:v2.11.0";
    ports = [ "2586:80" ];
    volumes = [
      "/config/ntfy:/etc/ntfy"
      "/var/lib/ntfy:/var/lib/ntfy"
    ];
    cmd = [ "serve" ];
    environment = {
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=ntfy"
      "--memory=128m"
    ];
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /config/ntfy 0750 root root -"
    "d /var/lib/ntfy 0750 root root -"
  ];
}
