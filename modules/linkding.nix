{ config, pkgs, ... }:

{
  # Linkding - bookmark manager (no NixOS module exists)
  virtualisation.oci-containers.containers.linkding = {
    image = "sissbruecker/linkding:latest-plus";
    ports = [ "9697:9090" ];
    volumes = [
      "/data/shared/bookmarks:/etc/linkding/data"
    ];
    environment = {
      TZ = "Asia/Singapore";
    };
    extraOptions = [
      "--name=linkding"
      "--memory=512m"
    ];
  };

  # Wait for mergerfs (data on mergerfs pool)
  systemd.services.docker-linkding = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
