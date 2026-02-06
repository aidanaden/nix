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
    # Note: HTTP/HTTPS ports (80, 443) are opened by caddy.nix
    # Note: DNS port (53) is opened by adguardhome.nix
    firewall = {
      enable = true;
      allowPing = true;

      # TCP ports
      allowedTCPPorts = [
        22     # SSH
        139    # Samba
        445    # Samba
        3000   # AdGuard Home web UI
        8096   # Jellyfin (direct access)
        9000   # Portainer (direct access)
      ];

      # UDP ports
      allowedUDPPorts = [
        137    # Samba
        138    # Samba
        443    # HTTP/3 QUIC (Caddy)
        41641  # Tailscale
      ];

      # Trust Tailscale interface completely
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  # Enable resolved for DNS
  services.resolved.enable = true;
}
