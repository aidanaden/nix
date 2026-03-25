{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.homeAutomation;
  yaml = pkgs.formats.yaml {};
  homeAssistantTrustedProxies = lib.concatMapStrings (proxy: "    - ${proxy}\n") cfg.homeAssistant.trustedProxies;
  homeAssistantAdvancedCameraCard = pkgs.fetchzip {
    url = "https://github.com/dermotduffy/advanced-camera-card/releases/download/v7.27.4/advanced-camera-card.zip";
    hash = "sha256-lBdJBn/TLU3ezZnUJLt4eH87n1pOizS68RfLHYyRUq0=";
  };
  homeAssistantLovelaceConfig = lib.optionalString (cfg.camera.host != null) ''
    lovelace:
      dashboards:
        frigate-cameras:
          mode: yaml
          title: Cameras
          icon: mdi:cctv
          show_in_sidebar: true
          filename: frigate-mobile-dashboard.yaml

    panel_iframe:
      frigate:
        title: Frigate
        icon: mdi:cctv
        url: ${cfg.homeAssistant.frigateExternalUrl}
  '';

  homeAssistantDashboard = pkgs.writeText "frigate-mobile-dashboard.yaml" ''
    title: Cameras
    views:
      - title: Studio
        path: studio
        icon: mdi:cctv
        cards:
          - type: custom:advanced-camera-card
            cameras:
              - id: ${cfg.camera.name}-hq
                title: Studio HQ
                camera_entity: camera.${cfg.camera.name}
                engine: frigate
                live_provider: go2rtc
                frigate:
                  camera_name: ${cfg.camera.name}
                  url: ${cfg.homeAssistant.frigateExternalUrl}
                go2rtc:
                  stream: ${cfg.camera.name}_main
                  modes:
                    - webrtc
                    - mse
                    - mp4
                dimensions:
                  aspect_ratio: "16:9"
                  layout:
                    fit: contain
              - id: ${cfg.camera.name}-fast
                title: Studio Fast
                camera_entity: camera.${cfg.camera.name}
                engine: frigate
                live_provider: go2rtc
                frigate:
                  camera_name: ${cfg.camera.name}
                  url: ${cfg.homeAssistant.frigateExternalUrl}
                go2rtc:
                  stream: ${cfg.camera.name}_sub
                  modes:
                    - webrtc
                    - mse
                    - mp4
                dimensions:
                  aspect_ratio: "16:9"
                  layout:
                    fit: contain
          - type: entities
            title: Alerts
            show_header_toggle: false
            entities:
              - entity: input_boolean.frigate_person_alerts
                name: Person alerts armed
              - entity: input_text.frigate_notify_action
                name: Mobile notify action
          - type: markdown
            content: |
              Use the camera menu to switch between `Studio HQ` and `Studio Fast` per client.

              Open the Frigate sidebar item for recordings, review, and deeper live stream controls.

              Set `Mobile notify action` to your Home Assistant phone notifier, for example `notify.mobile_app_your_phone`, then turn on `Person alerts armed` when you want person alerts.
  '';

  homeAssistantNotificationsPackage = pkgs.writeText "frigate_notifications.yaml" ''
    input_boolean:
      frigate_person_alerts:
        name: Frigate Person Alerts
        icon: mdi:motion-sensor
        initial: ${
      if cfg.homeAssistant.personAlertsEnabledByDefault
      then "true"
      else "false"
    }

    input_text:
      frigate_notify_action:
        name: Frigate Notify Action
        icon: mdi:cellphone-message
        max: 255
        initial: ${builtins.toJSON cfg.homeAssistant.mobileNotifyAction}

    automation:
      - id: frigate_mobile_person_alerts
        alias: Frigate Mobile Person Alerts
        mode: parallel
        max: 10
        trigger:
          - platform: mqtt
            topic: frigate/reviews
            payload: alert
            value_template: "{{ value_json['after']['severity'] }}"
        condition:
          - condition: state
            entity_id: input_boolean.frigate_person_alerts
            state: "on"
          - condition: template
            value_template: "{{ states(\"input_text.frigate_notify_action\") | trim != \"\" }}"
          - condition: template
            value_template: "{{ trigger.payload_json['type'] != 'end' }}"
          - condition: template
            value_template: "{{ trigger.payload_json['after']['data']['detections'] | count > 0 }}"
        action:
          - choose:
              - conditions:
                  - condition: template
                    value_template: "{{ states(\"input_text.frigate_notify_action\") == \"persistent_notification.create\" }}"
                sequence:
                  - service: persistent_notification.create
                    data:
                      title: ${builtins.toJSON "${lib.toUpper cfg.camera.name} Alert"}
                      message: >-
                        {{ trigger.payload_json['after']['data']['objects'] | map('replace', '_', ' ') | map('title') | join(', ') }} detected in ${cfg.camera.name}.
            default:
              - service: "{{ states('input_text.frigate_notify_action') }}"
                data:
                  title: ${builtins.toJSON "${lib.toUpper cfg.camera.name} Alert"}
                  message: >-
                    {{ trigger.payload_json['after']['data']['objects'] | map('replace', '_', ' ') | map('title') | join(', ') }} detected in ${cfg.camera.name}.
                  data:
                    image: ${builtins.toJSON "${cfg.homeAssistant.externalUrl}/api/frigate/notifications/{{ trigger.payload_json['after']['data']['detections'][0] }}/thumbnail.jpg"}
                    clickAction: ${builtins.toJSON cfg.homeAssistant.frigateExternalUrl}
                    url: ${builtins.toJSON cfg.homeAssistant.frigateExternalUrl}
                    tag: "{{ trigger.payload_json['after']['id'] }}"
                    when: "{{ trigger.payload_json['after']['start_time'] | int }}"
                    entity_id: "camera.{{ trigger.payload_json['after']['camera'] | replace('-', '_') | lower }}"
                    ttl: 0
                    priority: high
                    channel: Frigate Alerts
                    push:
                      interruption-level: time-sensitive
  '';

  homeAssistantConfig = pkgs.writeText "home-assistant-configuration.yaml" ''
    default_config:

    homeassistant:
      name: Aidan Mini
      time_zone: ${config.time.timeZone}
      packages: !include_dir_named packages

    frontend:
      extra_module_url:
        - /local/community/advanced-camera-card/advanced-camera-card.js

    http:
      use_x_forwarded_for: true
      trusted_proxies:
    ${homeAssistantTrustedProxies}
    stream:
    ffmpeg:
    media_source:
    ${homeAssistantLovelaceConfig}

    automation: !include automations.yaml
    script: !include scripts.yaml
    scene: !include scenes.yaml
  '';

  mosquittoConfig = pkgs.writeText "mosquitto.conf" ''
    persistence true
    persistence_location /mosquitto/data/
    log_dest stdout
    listener 1883
    allow_anonymous true
  '';

  frigateCameraConfig =
    if cfg.camera.host == null
    then {
      placeholder = {
        enabled = false;
        ffmpeg.inputs = [
          {
            path = "rtsp://127.0.0.1:8554/placeholder";
            roles = ["detect"];
          }
        ];
      };
    }
    else {
      "${cfg.camera.name}" = {
        ffmpeg.inputs = [
          {
            path = "rtsp://127.0.0.1:8554/${cfg.camera.name}_main";
            input_args = "preset-rtsp-restream";
            roles = ["record"];
          }
          {
            path = "rtsp://127.0.0.1:8554/${cfg.camera.name}_sub";
            input_args = "preset-rtsp-restream";
            roles = ["detect"];
          }
        ];
        detect = {
          enabled = true;
          width = cfg.camera.detectWidth;
          height = cfg.camera.detectHeight;
          fps = cfg.camera.detectFps;
        };
        live.streams = {
          "Main Stream" = "${cfg.camera.name}_main";
          "Sub Stream" = "${cfg.camera.name}_sub";
        };
        motion = {
          improve_contrast = true;
        };
      };
    };

  frigateConfig = yaml.generate "frigate.yml" ({
      mqtt = {
        host = "mqtt";
        port = 1883;
        topic_prefix = "frigate";
      };

      ffmpeg.hwaccel_args = "preset-vaapi";

      detectors.ov = {
        type = "openvino";
        device = "GPU";
      };

      model = {
        width = 300;
        height = 300;
        input_tensor = "nhwc";
        input_pixel_format = "bgr";
        path = "/openvino-model/ssdlite_mobilenet_v2.xml";
        labelmap_path = "/openvino-model/coco_91cl_bkgr.txt";
      };

      birdseye = {
        enabled = true;
      };

      detect = {
        enabled = true;
      };

      record = {
        enabled = true;
        continuous.days = 0;
        motion.days = cfg.frigate.retainDays;
        alerts.retain = {
          days = cfg.frigate.retainDays;
          mode = "motion";
        };
        detections.retain = {
          days = cfg.frigate.retainDays;
          mode = "motion";
        };
      };

      snapshots = {
        enabled = true;
        retain.default = cfg.frigate.retainDays;
      };

      review = {
        alerts.labels = ["person"];
        detections.labels = ["cat"];
      };

      objects.track = [
        "person"
        "cat"
      ];

      cameras = frigateCameraConfig;
    }
    // lib.optionalAttrs (cfg.camera.host != null) {
      go2rtc.streams = {
        "${cfg.camera.name}_main" = [
          "ffmpeg:rtsp://{FRIGATE_RTSP_USER}:{FRIGATE_RTSP_PASSWORD}@${cfg.camera.host}:${toString cfg.camera.rtspPort}${cfg.camera.mainStreamPath}"
        ];
        "${cfg.camera.name}_sub" = [
          "ffmpeg:rtsp://{FRIGATE_RTSP_USER}:{FRIGATE_RTSP_PASSWORD}@${cfg.camera.host}:${toString cfg.camera.rtspPort}${cfg.camera.subStreamPath}"
        ];
      };
    });

  archiveScript = pkgs.writeShellScript "frigate-review-archive" ''
    set -euo pipefail

    mqtt_host=127.0.0.1
    mqtt_port=${toString cfg.mqtt.loopbackPort}
    frigate_base=http://127.0.0.1:${toString cfg.frigate.internalPort}
    spool_dir="${cfg.archive.spoolDir}"
    remote_host="${cfg.archive.remoteHost}"
    remote_path="${cfg.archive.remotePath}"
    ssh_key="${cfg.archive.sshKeyPath}"

    mkdir -p "$spool_dir"

    ${pkgs.mosquitto}/bin/mosquitto_sub -h "$mqtt_host" -p "$mqtt_port" -t frigate/reviews -q 1 | \
      while IFS= read -r payload; do
        change_type="$(${pkgs.jq}/bin/jq -r '.type // empty' <<<"$payload")"
        if [ "$change_type" != "end" ]; then
          continue
        fi

        review_id="$(${pkgs.jq}/bin/jq -r '.after.id // empty' <<<"$payload")"
        event_id="$(${pkgs.jq}/bin/jq -r '.after.data.detections[0] // empty' <<<"$payload")"
        camera_name="$(${pkgs.jq}/bin/jq -r '.after.camera // "unknown"' <<<"$payload")"
        start_epoch="$(${pkgs.jq}/bin/jq -r '.after.start_time // 0 | floor' <<<"$payload")"

        if [ -z "$review_id" ] || [ -z "$event_id" ]; then
          echo "Skipping Frigate review archive without a detection-backed event id: $payload" >&2
          continue
        fi

        timestamp="$(date -u -d "@$start_epoch" +"%Y%m%dT%H%M%SZ")"
        camera_spool="$spool_dir/$camera_name"
        mkdir -p "$camera_spool"

        snapshot_file="$camera_spool/$timestamp-$review_id.jpg"
        clip_file="$camera_spool/$timestamp-$review_id.mp4"
        tmpdir="$(${pkgs.coreutils}/bin/mktemp -d)"

        cleanup() {
          rm -rf "$tmpdir"
        }

        trap cleanup EXIT

        if ! ${pkgs.curl}/bin/curl --fail --silent --show-error \
          "$frigate_base/api/events/$event_id/snapshot.jpg" \
          -o "$tmpdir/snapshot.jpg"; then
          echo "Snapshot download failed for Frigate event $event_id" >&2
          cleanup
          trap - EXIT
          continue
        fi

        if ! ${pkgs.curl}/bin/curl --fail --silent --show-error \
          "$frigate_base/api/events/$event_id/clip.mp4" \
          -o "$tmpdir/clip.mp4"; then
          echo "Clip download failed for Frigate event $event_id" >&2
          cleanup
          trap - EXIT
          continue
        fi

        install -Dm0640 "$tmpdir/snapshot.jpg" "$snapshot_file"
        install -Dm0640 "$tmpdir/clip.mp4" "$clip_file"

        if ${pkgs.openssh}/bin/ssh -i "$ssh_key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
          "$remote_host" "mkdir -p '$remote_path/$camera_name'" && \
          ${pkgs.rsync}/bin/rsync -az \
            -e "${pkgs.openssh}/bin/ssh -i $ssh_key -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
            "$snapshot_file" "$clip_file" "$remote_host:$remote_path/$camera_name/"; then
          rm -f "$snapshot_file" "$clip_file"
        else
          echo "Best-effort archive upload failed for review $review_id" >&2
        fi

        cleanup
        trap - EXIT
      done
  '';
in {
  options.homelab.homeAutomation = {
    enable = lib.mkEnableOption "Home Assistant, Frigate, and MQTT on aidan-mini";

    network = lib.mkOption {
      type = lib.types.str;
      default = "home-automation";
      description = "Docker network shared by Home Assistant, Frigate, and MQTT.";
    };

    homeAssistant = {
      imageTag = lib.mkOption {
        type = lib.types.str;
        default = "2026.3.3";
        description = "Pinned Home Assistant container tag.";
      };

      configDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/homeassistant";
        description = "Persistent Home Assistant config directory.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8123;
        description = "Host port for Home Assistant.";
      };

      trustedProxies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "172.18.0.1"
          "100.92.143.10"
          "192.168.0.69"
        ];
        description = "Reverse proxies allowed to forward requests to Home Assistant.";
      };

      externalUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://ha.aidanaden.com";
        description = "User-facing Home Assistant URL used in Frigate mobile notifications.";
      };

      frigateExternalUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://frigate.aidanaden.com";
        description = "User-facing Frigate URL for Home Assistant mobile navigation.";
      };

      mobileNotifyAction = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional Home Assistant notification action, for example notify.mobile_app_your_phone.";
      };

      personAlertsEnabledByDefault = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether Frigate person alerts start armed in Home Assistant.";
      };
    };

    mqtt = {
      imageTag = lib.mkOption {
        type = lib.types.str;
        default = "2";
        description = "Pinned Eclipse Mosquitto image tag.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/mosquitto";
        description = "Persistent Mosquitto data directory.";
      };

      loopbackPort = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "Loopback MQTT port for host-side helpers.";
      };
    };

    frigate = {
      imageTag = lib.mkOption {
        type = lib.types.str;
        default = "0.17.0";
        description = "Pinned Frigate container tag.";
      };

      configDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/frigate";
        description = "Persistent Frigate config directory.";
      };

      mediaDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/frigate/media";
        description = "Persistent Frigate media directory.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8971;
        description = "Host port for Frigate UI.";
      };

      internalPort = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "Loopback-only Frigate API port for local automation.";
      };

      retainDays = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Days to retain Frigate recordings and snapshots.";
      };
    };

    camera = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "studio";
        description = "Frigate camera name.";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "LAN IP or hostname of the Amcrest camera.";
      };

      rtspPort = lib.mkOption {
        type = lib.types.port;
        default = 554;
        description = "RTSP port exposed by the camera.";
      };

      mainStreamPath = lib.mkOption {
        type = lib.types.str;
        default = "/cam/realmonitor?channel=1&subtype=0";
        description = "RTSP path for the high-quality record stream.";
      };

      subStreamPath = lib.mkOption {
        type = lib.types.str;
        default = "/cam/realmonitor?channel=1&subtype=1";
        description = "RTSP path for the low-resolution detect stream.";
      };

      detectWidth = lib.mkOption {
        type = lib.types.int;
        default = 640;
        description = "Detect stream width.";
      };

      detectHeight = lib.mkOption {
        type = lib.types.int;
        default = 360;
        description = "Detect stream height.";
      };

      detectFps = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Frigate detect FPS.";
      };

      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Env file containing FRIGATE_RTSP_USER and FRIGATE_RTSP_PASSWORD.";
      };
    };

    archive = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Archive Frigate reviews to the NAS in near real time.";
      };

      remoteHost = lib.mkOption {
        type = lib.types.str;
        default = "aidan@100.92.143.10";
        description = "SSH destination for the NAS archive sync.";
      };

      remotePath = lib.mkOption {
        type = lib.types.str;
        default = "/srv/mergerfs/data/security/catcam/review";
        description = "Remote NAS path for Frigate review exports.";
      };

      sshKeyPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/home-automation/secrets/nas_archive_ed25519";
        description = "SSH private key used for Frigate review archive sync.";
      };

      spoolDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/home-automation/archive-spool";
        description = "Local best-effort spool for NAS archive uploads.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.homeAssistant.port != cfg.frigate.port;
        message = "Home Assistant and Frigate must not share the same host port.";
      }
      {
        assertion = cfg.frigate.internalPort != cfg.homeAssistant.port;
        message = "Frigate internal API port must not overlap Home Assistant.";
      }
    ];

    environment.systemPackages = with pkgs; [
      mosquitto
      rsync
    ];

    systemd.services.home-automation-docker-network = {
      description = "Ensure the home automation Docker network exists";
      wantedBy = ["multi-user.target"];
      after = ["docker.service"];
      requires = ["docker.service"];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect ${cfg.network} >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create ${cfg.network}
      '';
      preStop = ''
        ${pkgs.docker}/bin/docker network rm ${cfg.network} >/dev/null 2>&1 || true
      '';
    };

    systemd.services.home-automation-docker-forwarding = {
      description = "Allow the home automation Docker bridge to reach the LAN";
      wantedBy = ["multi-user.target"];
      after = [
        "docker.service"
        "firewall.service"
        "home-automation-docker-network.service"
      ];
      requires = [
        "docker.service"
        "home-automation-docker-network.service"
      ];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      script = ''
        network_id="$(${pkgs.docker}/bin/docker network inspect ${cfg.network} --format '{{ .Id }}')"
        bridge_name="br-$(printf '%s' "$network_id" | cut -c1-12)"

        ${pkgs.iptables}/bin/iptables -C FORWARD -i "$bridge_name" -j ACCEPT 2>/dev/null || \
          ${pkgs.iptables}/bin/iptables -I FORWARD 1 -i "$bridge_name" -j ACCEPT

        ${pkgs.iptables}/bin/iptables -C FORWARD -o "$bridge_name" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
          ${pkgs.iptables}/bin/iptables -I FORWARD 1 -o "$bridge_name" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
      '';
      preStop = ''
        network_id="$(${pkgs.docker}/bin/docker network inspect ${cfg.network} --format '{{ .Id }}' 2>/dev/null || true)"
        if [ -n "$network_id" ]; then
          bridge_name="br-$(printf '%s' "$network_id" | cut -c1-12)"
          ${pkgs.iptables}/bin/iptables -D FORWARD -i "$bridge_name" -j ACCEPT 2>/dev/null || true
          ${pkgs.iptables}/bin/iptables -D FORWARD -o "$bridge_name" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        fi
      '';
    };

    virtualisation.oci-containers.containers = {
      mqtt = {
        image = "eclipse-mosquitto:${cfg.mqtt.imageTag}";
        ports = ["127.0.0.1:${toString cfg.mqtt.loopbackPort}:1883"];
        volumes = [
          "${cfg.mqtt.dataDir}:/mosquitto/data"
          "${mosquittoConfig}:/mosquitto/config/mosquitto.conf:ro"
        ];
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [
          "--name=mqtt"
          "--memory=128m"
          "--network=${cfg.network}"
        ];
      };

      homeassistant = {
        image = "ghcr.io/home-assistant/home-assistant:${cfg.homeAssistant.imageTag}";
        ports = ["${toString cfg.homeAssistant.port}:8123"];
        dependsOn = ["mqtt"];
        volumes = [
          "${cfg.homeAssistant.configDir}:/config"
          "${homeAssistantConfig}:/config/configuration.yaml:ro"
          "${homeAssistantDashboard}:/config/frigate-mobile-dashboard.yaml:ro"
          "${homeAssistantNotificationsPackage}:/config/packages/frigate_notifications.yaml:ro"
          "${homeAssistantAdvancedCameraCard}:/config/www/community/advanced-camera-card:ro"
        ];
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [
          "--name=homeassistant"
          "--memory=1024m"
          "--network=${cfg.network}"
        ];
      };

      frigate = {
        image = "ghcr.io/blakeblackshear/frigate:${cfg.frigate.imageTag}";
        ports = [
          "${toString cfg.frigate.port}:8971"
          "127.0.0.1:${toString cfg.frigate.internalPort}:5000"
        ];
        dependsOn = ["mqtt"];
        volumes = [
          "${cfg.frigate.configDir}:/config"
          "${frigateConfig}:/config/config.yml:ro"
          "${cfg.frigate.mediaDir}:/media/frigate"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environment =
          {
            TZ = config.time.timeZone;
            LIBVA_DRIVER_NAME = "iHD";
          }
          // lib.optionalAttrs (cfg.camera.host == null || cfg.camera.credentialsFile == null) {
            FRIGATE_RTSP_USER = "";
            FRIGATE_RTSP_PASSWORD = "";
          };
        environmentFiles =
          lib.optional
          (cfg.camera.host != null && cfg.camera.credentialsFile != null)
          cfg.camera.credentialsFile;
        extraOptions = [
          "--name=frigate"
          "--memory=2048m"
          "--network=${cfg.network}"
          "--device=/dev/dri/renderD128:/dev/dri/renderD128"
          "--shm-size=512m"
          "--tmpfs=/tmp/cache:size=1000000000"
        ];
      };
    };

    systemd.services.docker-mqtt = {
      after = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
      requires = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
    };

    systemd.services.docker-homeassistant = {
      after = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
      requires = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
    };

    systemd.services.docker-frigate = {
      after = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
      requires = [
        "home-automation-docker-network.service"
        "home-automation-docker-forwarding.service"
      ];
    };

    systemd.services.home-automation-tailscale-firewall = {
      description = "Restrict Home Assistant and Frigate Docker ports to Tailscale";
      wantedBy = ["multi-user.target"];
      after = ["docker.service" "firewall.service"];
      requires = ["docker.service"];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      script = ''
        for port in ${toString cfg.homeAssistant.port} ${toString cfg.frigate.port}; do
          ${pkgs.iptables}/bin/iptables -C DOCKER-USER -i tailscale0 -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
            ${pkgs.iptables}/bin/iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport "$port" -j ACCEPT
          ${pkgs.iptables}/bin/iptables -C DOCKER-USER ! -i tailscale0 -p tcp --dport "$port" -j DROP 2>/dev/null || \
            ${pkgs.iptables}/bin/iptables -I DOCKER-USER 2 ! -i tailscale0 -p tcp --dport "$port" -j DROP
        done
      '';
      preStop = ''
        for port in ${toString cfg.homeAssistant.port} ${toString cfg.frigate.port}; do
          ${pkgs.iptables}/bin/iptables -D DOCKER-USER -i tailscale0 -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
          ${pkgs.iptables}/bin/iptables -D DOCKER-USER ! -i tailscale0 -p tcp --dport "$port" -j DROP 2>/dev/null || true
        done
      '';
    };

    systemd.services.frigate-review-archive = lib.mkIf cfg.archive.enable {
      description = "Archive Frigate review clips to the NAS";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = [
        "docker-mqtt.service"
        "docker-frigate.service"
        "network-online.target"
      ];
      requires = [
        "docker-mqtt.service"
        "docker-frigate.service"
      ];
      unitConfig.ConditionPathExists = cfg.archive.sshKeyPath;
      path = [pkgs.coreutils];
      serviceConfig = {
        ExecStart = archiveScript;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.homeAssistant.configDir} 0750 root root -"
      "f ${cfg.homeAssistant.configDir}/automations.yaml 0640 root root -"
      "f ${cfg.homeAssistant.configDir}/scripts.yaml 0640 root root -"
      "f ${cfg.homeAssistant.configDir}/scenes.yaml 0640 root root -"
      "d ${cfg.homeAssistant.configDir}/custom_components 0750 root root -"
      "d ${cfg.homeAssistant.configDir}/packages 0750 root root -"
      "r ${cfg.homeAssistant.configDir}/packages/frigate-notifications.yaml - - - -"
      "d ${cfg.homeAssistant.configDir}/www 0750 root root -"
      "d ${cfg.mqtt.dataDir} 0750 root root -"
      "d ${cfg.frigate.configDir} 0750 root root -"
      "d ${cfg.frigate.mediaDir} 0750 root root -"
      "d ${cfg.frigate.mediaDir}/clips 0750 root root -"
      "d ${cfg.frigate.mediaDir}/exports 0750 root root -"
      "d ${cfg.frigate.mediaDir}/recordings 0750 root root -"
      "d ${cfg.frigate.mediaDir}/snapshots 0750 root root -"
      "d /var/lib/home-automation 0750 root root -"
      "d /var/lib/home-automation/secrets 0700 root root -"
      "d ${cfg.archive.spoolDir} 0750 root root -"
    ];
  };
}
