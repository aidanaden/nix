{pkgs, ...}: {
  systemd.services.docker-control-network = {
    description = "Ensure the Docker control network exists";
    wantedBy = ["multi-user.target"];
    after = ["docker.service"];
    requires = ["docker.service"];
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
    };
    script = ''
      ${pkgs.docker}/bin/docker network inspect docker-control >/dev/null 2>&1 || \
        ${pkgs.docker}/bin/docker network create docker-control
    '';
    preStop = ''
      ${pkgs.docker}/bin/docker network rm docker-control >/dev/null 2>&1 || true
    '';
  };

  virtualisation.oci-containers.containers.docker-socket-proxy = {
    image = "tecnativa/docker-socket-proxy:v0.4.2";
    ports = ["127.0.0.1:2375:2375"];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    environment = {
      ALLOW_START = "1";
      ALLOW_STOP = "1";
      CONTAINERS = "1";
      EVENTS = "1";
      IMAGES = "1";
      INFO = "1";
      PING = "1";
      POST = "1";
      VERSION = "1";
    };
    extraOptions = [
      "--name=docker-socket-proxy"
      "--memory=64m"
      "--network=docker-control"
    ];
  };

  systemd.services.docker-docker-socket-proxy = {
    after = ["docker-control-network.service"];
    requires = ["docker-control-network.service"];
  };
}
