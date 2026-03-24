{config, ...}: let
  mergerfsDeps = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };
in {
  # Linkding - bookmark manager (no NixOS module exists)
  virtualisation.oci-containers.containers.linkding = {
    image = "sissbruecker/linkding:1.45.0-plus";
    ports = ["9697:9090"];
    volumes = [
      "/data/shared/bookmarks:/etc/linkding/data"
    ];
    environment = {
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--name=linkding"
      "--memory=512m"
    ];
  };

  # Wait for mergerfs (data on mergerfs pool)
  systemd.services.docker-linkding = mergerfsDeps;
}
