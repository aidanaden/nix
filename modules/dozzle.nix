{config, ...}: {
  # Dozzle - real-time Docker log viewer
  virtualisation.oci-containers.containers.dozzle = {
    image = "amir20/dozzle:v8.12.6";
    ports = ["127.0.0.1:9010:8080"];
    environment = {
      TZ = config.time.timeZone;
      DOZZLE_NO_ANALYTICS = "true";
      DOZZLE_REMOTE_HOST = "tcp://docker-socket-proxy:2375|aidan-nas";
    };
    extraOptions = [
      "--name=dozzle"
      "--memory=128m"
      "--network=docker-control"
    ];
  };

  systemd.services.docker-dozzle = {
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
