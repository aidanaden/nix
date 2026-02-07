{ config, pkgs, ... }:

{
  services.bazarr = {
    enable = true;
    listenPort = 6767;
    group = "users";
  };

  # Wait for mergerfs (subtitles for media on data disks)
  systemd.services.bazarr = {
    after = [ "mergerfs.service" ];
    requires = [ "mergerfs.service" ];
  };
}
