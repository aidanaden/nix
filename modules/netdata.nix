{config, ...}: {
  # Netdata - real-time system monitoring
  # Auto-discovers: disks, containers, CPU, RAM, temps, network
  virtualisation.oci-containers.containers.netdata = {
    image = "netdata/netdata:v2.3.0";
    # Uses host networking (see extraOptions), so explicit port publishing is unnecessary.
    volumes = [
      "/config/netdata:/etc/netdata"
      "/var/lib/netdata:/var/lib/netdata"
      "/etc/passwd:/host/etc/passwd:ro"
      "/etc/group:/host/etc/group:ro"
      "/etc/localtime:/etc/localtime:ro"
      "/proc:/host/proc:ro"
      "/sys:/host/sys:ro"
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    environment = {
      TZ = config.time.timeZone;
      NETDATA_CLAIM_TOKEN = ""; # Leave empty for local-only mode
    };
    extraOptions = [
      "--name=netdata"
      "--memory=512m"
      "--cap-add=SYS_PTRACE"
      "--cap-add=SYS_ADMIN"
      "--security-opt=apparmor=unconfined"
      "--pid=host"
      "--network=host"
    ];
  };

  # Ensure config directory exists
  systemd.tmpfiles.rules = [
    "d /config/netdata 0755 root root -"
    "d /var/lib/netdata 0755 root root -"
  ];
}
