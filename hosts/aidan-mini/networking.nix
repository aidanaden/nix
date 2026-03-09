_: {
  networking = {
    hostName = "aidan-mini";
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowPing = true;

      allowedTCPPorts = [
        22
      ];

      trustedInterfaces = ["tailscale0"];
    };
  };

  services.resolved.enable = true;
}
