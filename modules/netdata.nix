{pkgs, ...}: {
  # Netdata - real-time system monitoring
  # Auto-discovers: disks, containers, CPU, RAM, temps, and network.
  services.netdata = {
    enable = true;
    config.web = {
      "bind to" = "127.0.0.1";
    };
    configDir."go.d/docker.conf" = pkgs.writeText "netdata-docker.conf" ''
      jobs:
        - name: local
          address: tcp://127.0.0.1:2375
    '';
  };

  systemd.services.netdata = {
    after = [
      "docker-control-network.service"
      "docker-docker-socket-proxy.service"
    ];
    requires = [
      "docker-control-network.service"
      "docker-docker-socket-proxy.service"
    ];
  };
}
