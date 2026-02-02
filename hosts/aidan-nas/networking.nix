{ config, pkgs, ... }:

{
  networking = {
    hostName = "aidan-nas";

    # Static IP configuration
    useDHCP = false;
    interfaces.enp3s0 = {
      ipv4.addresses = [{
        address = "192.168.0.69";
        prefixLength = 24;
      }];
    };
    defaultGateway = "192.168.0.1";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];

    # Firewall
    firewall = {
      enable = true;
      allowPing = true;

      # TCP ports
      allowedTCPPorts = [
        22     # SSH
        80     # HTTP
        443    # HTTPS
        139    # Samba
        445    # Samba
        53     # Pi-hole DNS
        8053   # Pi-hole web
        8096   # Jellyfin
        9000   # Portainer
        51821  # WireGuard UI
      ];

      # UDP ports
      allowedUDPPorts = [
        53     # Pi-hole DNS
        137    # Samba
        138    # Samba
        41641  # Tailscale
        51820  # WireGuard
      ];
    };
  };

  # Enable resolved for DNS
  services.resolved.enable = true;
}
