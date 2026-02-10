{pkgs, ...}: {
  # Data disk mounts (by UUID - preserved from OMV)
  # These are NOT touched by disko, only mounted
  fileSystems = {
    "/srv/disk1" = {
      device = "/dev/disk/by-uuid/48e46356-3374-4198-a5f2-fe1683b4a675";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk2" = {
      device = "/dev/disk/by-uuid/f7609add-b8af-4045-bf46-a6a4954b52ef";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk3" = {
      device = "/dev/disk/by-uuid/59990e40-4545-4024-8201-170449926f30";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk4" = {
      device = "/dev/disk/by-uuid/adaa0676-75c8-4193-8663-fa170324a134";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk5" = {
      device = "/dev/disk/by-uuid/0805c2d3-9704-4870-a253-60a6ec9c429c";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk6" = {
      device = "/dev/disk/by-uuid/65193c76-48d3-48d8-bcee-837cf381dd47";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk7" = {
      device = "/dev/disk/by-uuid/9287a573-8dc5-4ae8-b362-4c8c80343984";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
    "/srv/disk8" = {
      device = "/dev/disk/by-uuid/15b064c3-da6e-4476-b141-19833c2acff9";
      fsType = "ext4";
      options = ["noatime" "nofail"];
    };
  };

  # mergerfs pool - combines all data disks
  systemd.services.mergerfs = {
    description = "mergerfs pool";
    after = [
      "srv-disk1.mount"
      "srv-disk2.mount"
      "srv-disk3.mount"
      "srv-disk4.mount"
      "srv-disk5.mount"
      "srv-disk6.mount"
      "srv-disk7.mount"
      "srv-disk8.mount"
    ];
    requires = [
      "srv-disk1.mount"
      "srv-disk2.mount"
      "srv-disk3.mount"
      "srv-disk4.mount"
      "srv-disk5.mount"
      "srv-disk6.mount"
      "srv-disk7.mount"
      "srv-disk8.mount"
    ];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.mergerfs}/bin/mergerfs \
          /srv/disk1:/srv/disk2:/srv/disk3:/srv/disk4:/srv/disk5:/srv/disk6:/srv/disk7:/srv/disk8 \
          /srv/mergerfs/data \
          -o defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs
      '';
      ExecStop = "${pkgs.fuse}/bin/fusermount -uz /srv/mergerfs/data";
      Restart = "on-failure";
    };
  };

  # Create mergerfs mount point and symlinks for compatibility
  # /data -> /srv/mergerfs/data
  # /config -> /srv/mergerfs/data/config
  # /compose -> /srv/mergerfs/data/compose
  systemd.tmpfiles.rules = [
    "d /srv/mergerfs/data 0755 root root -"
    "L+ /data - - - - /srv/mergerfs/data"
    "L+ /config - - - - /srv/mergerfs/data/config"
    "L+ /compose - - - - /srv/mergerfs/data/compose"
  ];

  # Swap file on SSD
  swapDevices = [
    {
      device = "/var/swapfile";
      size = 8192; # 8GB
    }
  ];
}
