{
  config,
  lib,
  ...
}: {
  services.tailscale = {
    enable = true;
    useRoutingFeatures = lib.mkDefault "server";
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
    "net.ipv4.ip_forward" = lib.mkDefault 1;
    "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
  };
}
