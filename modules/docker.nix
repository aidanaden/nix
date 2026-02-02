{ config, pkgs, ... }:

{
  # Docker
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" "--volumes" ];
    };
    daemon.settings = {
      # Log rotation
      log-driver = "json-file";
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
      # Storage driver
      storage-driver = "overlay2";
    };
  };

  # Docker Compose
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # Ensure docker group exists
  users.groups.docker = { };
}
