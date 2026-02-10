{pkgs, ...}: {
  # Docker
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = ["--all"];
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

  # Ensure oci-containers uses Docker (matches Sablier's Docker provider + docker.sock usage).
  virtualisation.oci-containers.backend = "docker";

  # Docker Compose
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # Ensure docker group exists
  users.groups.docker = {};
}
