_: {
  services.jellyfin = {
    enable = true;
    dataDir = "/config/jellyfin";
    openFirewall = true;
  };

  # Jellyfin needs access to media files
  users.users.jellyfin.extraGroups = ["users"];

  # Wait for mergerfs (config + media on data disks)
  systemd.services.jellyfin = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };
}
