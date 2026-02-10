{config, ...}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    # Auth key from sops-nix secrets
    authKeyFile = config.sops.secrets.tailscale_auth_key.path;
  };

  # Open firewall for Tailscale
  networking.firewall = {
    trustedInterfaces = ["tailscale0"];
    allowedUDPPorts = [config.services.tailscale.port];
  };

  # Enable IP forwarding for subnet routing (if needed)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
