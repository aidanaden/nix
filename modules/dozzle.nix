{config, ...}: {
  # Dozzle - real-time Docker log viewer
  virtualisation.oci-containers.containers.dozzle = {
    image = "amir20/dozzle:v8.12.6";
    ports = ["9010:8080"];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    environment = {
      TZ = config.time.timeZone;
      DOZZLE_NO_ANALYTICS = "true";
    };
    extraOptions = [
      "--name=dozzle"
      "--memory=128m"
    ];
  };
}
