_: {
  # Syncthing - P2P device sync (replaces Nextcloud for file sync)
  services.syncthing = {
    enable = true;
    user = "aidan";
    group = "users";
    dataDir = "/data/shared/syncthing";
    configDir = "/config/syncthing";

    openDefaultPorts = true; # 22000/tcp + 22000/udp (sync) + 21027/udp (discovery)

    settings = {
      gui = {
        # Listen on all interfaces (reverse proxied through Caddy)
        address = "0.0.0.0:8384";
      };

      options = {
        urAccepted = -1; # Disable usage reporting
        relaysEnabled = true; # Allow relay connections for NAT traversal
        localAnnounceEnabled = true;
        globalAnnounceEnabled = true;
      };
    };

    # Allow Syncthing to manage its own config (folders, devices)
    overrideFolders = false;
    overrideDevices = false;
  };

  # Wait for mergerfs (data on data disks)
  systemd.services.syncthing = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /data/shared/syncthing 0750 aidan users -"
    "d /config/syncthing 0750 aidan users -"
  ];
}
