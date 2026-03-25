# aidan-mini Home Automation Stack

## What the repo now manages

- Home Assistant in Docker on port `8123`
- Frigate in Docker on HTTPS port `8971`
- Mosquitto in Docker on loopback port `1883`
- A dedicated Docker network for the stack
- Tailscale-only exposure for Home Assistant and Frigate via `DOCKER-USER`
- A best-effort Frigate review archive worker that pushes snapshot + clip pairs to `aidan-nas`

## Required local files before deployment

Create the Amcrest credentials file on `aidan-mini`:

```bash
sudo install -d -m 0700 /var/lib/home-automation/secrets
sudo tee /var/lib/home-automation/secrets/amcrest.env >/dev/null <<'EOF'
FRIGATE_RTSP_USER=homeassistant
FRIGATE_RTSP_PASSWORD=replace-me
EOF
sudo chmod 0600 /var/lib/home-automation/secrets/amcrest.env
```

Create an SSH key for NAS archive sync and authorize it on `aidan-nas`:

```bash
sudo ssh-keygen -t ed25519 -N '' -f /var/lib/home-automation/secrets/nas_archive_ed25519
sudo chmod 0600 /var/lib/home-automation/secrets/nas_archive_ed25519
sudo cat /var/lib/home-automation/secrets/nas_archive_ed25519.pub
```

Append that public key to `~/.ssh/authorized_keys` for `aidan` on `aidan-nas`.

## Required repo edits before deployment

Fill in the camera IP in [hosts/aidan-mini/default.nix](/Users/aidan/projects/nixos-machines/hosts/aidan-mini/default.nix) once the Archer NX200 has reserved it.

The stack will still build with `camera.host = null`, but Frigate will run in a placeholder state until the camera address is set.

## Home Assistant post-deploy steps

1. Finish Home Assistant onboarding and create the admin user.
2. MQTT and the Frigate integration are now wired into the live HA instance already.
   - MQTT host: `mqtt`
   - MQTT port: `1883`
   - Frigate URL: `http://frigate:5000`
   - HA now prefers the higher-quality Frigate main restream via `rtsp://frigate:8554/{{ name }}_main`
3. Install the custom Amcrest integration from:
   - `https://github.com/bcpearce/HomeAssistant-Amcrest-Custom`
4. Add the Amcrest camera through the custom integration if you want direct Amcrest control entities in HA.
5. Confirm the HA sidebar items:
   - `Cameras` YAML dashboard
   - `Frigate` panel link
6. The `Cameras` dashboard now bundles `advanced-camera-card` declaratively and points it at Frigate go2rtc stream `studio_main` for the highest-quality HA live view.

## Mobile UX defaults

The repo now prewires a better HA mobile experience:

- Home Assistant shows a `Cameras` dashboard that uses `advanced-camera-card` with `camera.studio`
- The dashboard live view prefers the Frigate `studio_main` go2rtc stream instead of the stock HA `picture-entity` camera card
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

## Privacy and presence

The repo sets up the infrastructure only. The privacy automation still needs to be created inside Home Assistant because the final entity IDs come from:

- the iPhone Home Assistant companion app
- the custom Amcrest integration
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
