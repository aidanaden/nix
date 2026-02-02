{ config, pkgs, ... }:

{
  services.samba = {
    enable = true;
    securityType = "user";
    openFirewall = true;

    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "aidan-nas";
        "netbios name" = "aidan-nas";
        "security" = "user";
        "hosts allow" = "192.168.0. 100. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
        # Performance tuning
        "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
        "read raw" = "yes";
        "write raw" = "yes";
        "use sendfile" = "yes";
        "aio read size" = "16384";
        "aio write size" = "16384";
      };

      # Main data share
      "data" = {
        "path" = "/srv/mergerfs/data";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "aidan";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "aidan";
        "force group" = "users";
      };

      # Media share (read-only for most)
      "media" = {
        "path" = "/srv/mergerfs/data/shared/media";
        "browseable" = "yes";
        "read only" = "yes";
        "guest ok" = "yes";
        "write list" = "aidan";
      };
    };
  };

  # Samba user (password set manually: sudo smbpasswd -a aidan)
  # Note: Samba users must also exist as system users
}
