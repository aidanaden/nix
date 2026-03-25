# aidan-mini Home Automation Stack

## What the repo now manages

- Home Assistant in Docker on port `8123`
- Frigate in Docker on HTTPS port `8971`
- Mosquitto in Docker on loopback port `1883`
- A dedicated Docker network for the stack
- Tailscale-only exposure for Home Assistant and Frigate via `DOCKER-USER`
- A best-effort Frigate review archive worker that pushes snapshot + clip pairs to `aidan-nas`

## Required local files before deployment

Create an SSH key for NAS archive sync and authorize it on `aidan-nas`:

```bash
sudo ssh-keygen -t ed25519 -N '' -f /var/lib/home-automation/secrets/nas_archive_ed25519
sudo chmod 0600 /var/lib/home-automation/secrets/nas_archive_ed25519
sudo cat /var/lib/home-automation/secrets/nas_archive_ed25519.pub
```

Append that public key to `~/.ssh/authorized_keys` for `aidan` on `aidan-nas`.

## Required repo edits before deployment

Camera credentials now come from `sops`, not a host-local env file. Update the encrypted values in [secrets/secrets.yaml](/Users/aidan/projects/nixos-machines/secrets/secrets.yaml) when the camera password changes, then redeploy `aidan-mini`.

Keep the reserved camera host in [hosts/aidan-mini/default.nix](/Users/aidan/projects/nixos-machines/hosts/aidan-mini/default.nix) aligned with the Archer NX200 lease. The current Wi‑Fi lease is `192.168.1.6`.

## Home Assistant post-deploy steps

1. Finish Home Assistant onboarding and create the admin user.
2. MQTT and the Frigate integration are now wired into the live HA instance already.
   - MQTT host: `mqtt`
   - MQTT port: `1883`
   - Frigate URL: `http://frigate:5000`
   - HA now prefers the higher-quality Frigate main restream via `rtsp://frigate:8554/{{ name }}_main`
3. Confirm the HA sidebar items:
   - `Cameras` YAML dashboard
   - `Frigate` panel link
4. The `Cameras` dashboard now uses native HA cards for stability:
   - `Studio` shows the higher-quality Frigate-backed HA camera entity
   - `HQ` and `Fast` buttons open Frigate for stream switching and review
5. The same dashboard also includes built-in Amcrest controls from the native HA integration:
   - `Privacy mode` switch
   - `Camera online` status
   - directional PTZ controls wired to `amcrest.ptz_control`
6. The repo now bundles these HA custom integrations declaratively:
   - `HACS` backend
   - `Alarmo` backend
7. In the HA UI, finish the app-level setup:
   - add the `HACS` integration and complete its GitHub/device auth flow
   - add the `Alarmo` integration from `Settings > Devices & Services`
   - use the native HA Alarm Panel card with the Alarmo entity after you create your alarm

## Mobile UX defaults

The repo now prewires a better HA mobile experience:

- Home Assistant shows a stable native `Cameras` dashboard with `camera.studio`
- The dashboard defaults to the higher-quality stream
- `HQ` and `Fast` buttons open Frigate, which remains the place for live stream selection
- The dashboard also exposes Amcrest privacy and PTZ controls directly in HA
- Home Assistant also shows a `Frigate` sidebar panel that opens `https://frigate.aidanaden.com`
- Home Assistant now also exposes:
  - `input_boolean.frigate_person_alerts`
  - `input_text.frigate_notify_action`
- The HA app should be your primary mobile surface, while the Frigate panel is the deeper review UI

## Mobile alerts

Frigate person alerts are now wired declaratively in Home Assistant, but they stay inert until you point them at a phone notifier.

1. Install the Home Assistant mobile app and sign into `https://ha.aidanaden.com`
2. Allow notifications on the phone
3. In HA, set `input_text.frigate_notify_action` to your phone's notification action
   - example: `notify.mobile_app_your_phone`
   - HA-only fallback for testing: `persistent_notification.create`
4. Turn on `input_boolean.frigate_person_alerts` when you want person alerts armed

The automation listens to `frigate/reviews` with `severity = alert`, so cat-only detections stay reviewable in Frigate but do not notify.

## Frigate tuning defaults

Frigate is now tuned conservatively for the current studio layout:

- `person` alert reviews require the `entry` zone
- `person` and `cat` both remain reviewable as detections outside that zone
- `birdseye` is set to `objects`
- motion masks exclude the timestamp and Amcrest overlays
- a `bed` zone is scaffolded for later cat-specific automations

Current goal:

- person alerts should bias toward meaningful entry/walkway activity
- cat movement should stay reviewable without creating push spam
- static overlays should not waste motion processing

These coordinates are tuned to the current camera angle. If you remount or significantly pan/tilt the camera, retune the Frigate masks and zones.

## HA Frigate Sync Tool

If the live Home Assistant Frigate config ever drifts, reapply the repo's expected HA integration settings with:

```bash
nix run '.#sync-ha-frigate' -- --deploy-host aidan-mini
```

This tool:

- ensures the MQTT config entry exists
- ensures the Frigate config entry exists
- sets the Frigate `rtsp_url_template` to `rtsp://frigate:8554/{{ name }}_main`

It assumes Home Assistant onboarding is already complete and the Frigate custom integration is already installed in HA.

## Camera setup checklist

On the Amcrest camera:

- reserve a DHCP lease on the Archer NX200
- disable vendor cloud or P2P features
- disable UPnP
- use H.264 on both the main stream and substream
- keep the SD card enabled as a fallback recorder
- create a dedicated local user for Frigate
- create a PTZ preset that visibly faces the wall or base for privacy mode

The repo now also uses `aidan-mini` as the camera's LAN NTP server:

- `chronyd` listens on UDP `123` on the LAN
- `amcrest-ntp-sync.service` points the camera at `aidan-mini` and does an immediate `setCurrentTime`
- rerun it manually with `sudo systemctl start amcrest-ntp-sync.service` if you ever need to force a resync

## CI validation

The repo now exposes a generated Home Assistant config directory for CI:

```bash
nix build .#homeassistant-ci-aidan-mini
```

This output mirrors the declarative HA config, packages, and bundled custom integrations closely enough for `frenck/action-home-assistant` to run a config check in GitHub Actions.

## Privacy and presence

The repo now exposes the core Amcrest entities in HA directly. Privacy automation still needs to be created inside Home Assistant because the presence inputs come from:

- the iPhone Home Assistant companion app
- the built-in Amcrest integration
- the Wi-Fi SSID sensor exposed by the companion app

Recommended HA automation behavior:

- enter privacy only after `person.aidan` is home and the iPhone Wi-Fi SSID confirms home for 5 minutes
- use the Amcrest `privacy_mode` entity and the PTZ privacy preset together
- exit privacy quickly when the phone leaves home
- if Home Assistant thinks you are away but the camera remains private for 5 minutes, auto-arm and alert

## Archer NX200 WAN-block test

The target end state is:

- local LAN access from `aidan-mini` to the camera works
- outbound internet access from the camera does not work

Test this in the Archer NX200 UI or Tether app using device-level access control or parental controls. If the NX200 cannot reliably enforce LAN-only camera access, treat that as an unfinished hardening step and solve it before trusting the camera for privacy-sensitive use.
