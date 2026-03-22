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
2. Install HACS.
3. Install the custom Amcrest integration from:
   - `https://github.com/bcpearce/HomeAssistant-Amcrest-Custom`
4. Install `advanced-camera-card`.
5. Add the Frigate integration in Home Assistant.
6. Add the Amcrest camera through the custom integration.
7. Install a Frigate mobile notification blueprint such as:
   - `https://github.com/SgtBatten/HA_blueprints`

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
