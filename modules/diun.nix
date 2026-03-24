{config, ...}: {
  # DIUN - Docker Image Update Notifier
  # Monitors all running containers for image updates, notifies via Telegram.
  # Does NOT auto-update — notify-only (safer than Watchtower).
  virtualisation.oci-containers.containers.diun = {
    image = "crazymax/diun:4.28.0";
    volumes = [
      "diun-data:/data"
    ];
    environment = {
      TZ = config.time.timeZone;
      # Check for updates daily at 6am
      DIUN_WATCH_SCHEDULE = "0 6 * * *";
      DIUN_WATCH_JITTER = "30s";
      # Monitor all Docker containers by default
      DIUN_PROVIDERS_DOCKER = "true";
      DIUN_PROVIDERS_DOCKER_ENDPOINT = "tcp://docker-socket-proxy:2375";
      DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT = "true";
      # Telegram notifications
      DIUN_NOTIF_TELEGRAM = "true";
    };
    # sops-nix template provides DIUN_NOTIF_TELEGRAM_TOKEN and DIUN_NOTIF_TELEGRAM_CHATIDS
    environmentFiles = [
      config.sops.templates."diun-env".path
    ];
    extraOptions = [
      "--name=diun"
      "--network=docker-control"
    ];
  };

  systemd.services.docker-diun = {
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
