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

      # SSH
      allowedTCPPorts = [ 22 ];

      # HTTP/HTTPS (Caddy)
      allowedTCPPorts = [ 80 443 ];

      # Samba
      allowedTCPPorts = [ 139 445 ];
      allowedUDPPorts = [ 137 138 ];

      # Jellyfin
      allowedTCPPorts = [ 8096 ];

      # Tailscale (handled by tailscale module, but explicit)
      allowedUDPPorts = [ 41641 ];

      # WireGuard
      allowedUDPPorts = [ 51820 ];

      # Various services (Docker containers)
      # These are typically accessed via reverse proxy (Caddy)
      # but opening for direct LAN access
      allowedTCPPorts = [
        22     # SSH
        80     # HTTP
        443    # HTTPS
        139    # Samba
        445    # Samba
        8096   # Jellyfin
        9000   # Portainer
        8053   # Pi-hole web
        53     # Pi-hole DNS
        51821  # WireGuard UI
      ];

      allowedUDPPorts = [
        137    # Samba
        138    # Samba
        53     # Pi-hole DNS
        41641  # Tailscale
        51820  # WireGuard
      ];
    };
  };

  # Enable resolved for DNS
  services.resolved.enable = true;
}
