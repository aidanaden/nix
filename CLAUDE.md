# NixOS Machines

NixOS configurations for personal infrastructure.

## Hosts

| Host        | Hardware                            | Purpose                 | Status   |
| ----------- | ----------------------------------- | ----------------------- | -------- |
| `aidan-nas` | Intel i5-2400S, 16GB RAM, 8x WD Red | Home NAS + media server | Planning |

## Quick Reference

### NAS Details

- **LAN IP:** 192.168.0.69
- **Tailscale IP:** 100.92.143.10
- **SSH:** `ssh aidan@100.92.143.10`
- **Domain:** `*.aidanaden.com`

### Commands

```bash
# Build NixOS config (check for errors)
nix build .#nixosConfigurations.aidan-nas.config.system.build.toplevel

# Deploy with nixos-anywhere (DESTRUCTIVE - reformats OS disk)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#aidan-nas \
  root@100.92.143.10

# Update flake inputs
nix flake update

# Deploy backup scripts to NAS
scp scripts/backup-*.sh aidan@100.92.143.10:/usr/local/bin/
ssh aidan@100.92.143.10 "sudo chmod +x /usr/local/bin/backup-*.sh"
```

### Secrets Management (sops-nix)

```bash
# Generate age key (one-time)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Edit secrets
sops secrets/secrets.yaml

# Re-encrypt after adding new keys
sops updatekeys secrets/secrets.yaml
```

### Authelia Setup

```bash
# Generate password hash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password 'YOUR_PASSWORD'

# Copy hash to compose/authelia/users_database.yml
```

## Project Structure

```
.
├── flake.nix                 # Nix flake entry point
├── flake.lock
├── CLAUDE.md                 # This file
├── AGENTS.md -> CLAUDE.md    # Symlink
│
├── hosts/
│   └── aidan-nas/            # NAS configuration
│       ├── default.nix       # Main config (imports all)
│       ├── disko.nix         # OS disk partitioning (sda only)
│       ├── hardware.nix      # Hardware-specific settings
│       ├── filesystems.nix   # Data disks + mergerfs mounts
│       ├── networking.nix    # Static IP, firewall, Tailscale
│       └── users.nix         # Users + SSH keys
│
├── modules/                  # Reusable NixOS modules
│   ├── docker.nix
│   ├── samba.nix
│   ├── tailscale.nix
│   └── maintenance.nix
│
├── compose/                  # Docker Compose files
│   ├── authelia/             # SSO with TOTP
│   ├── caddy/                # Reverse proxy + Sablier
│   └── ntfy/                 # Notifications (placeholder)
│
├── scripts/                  # Maintenance scripts
│   ├── backup-critical.sh    # Vaultwarden + compose (daily 2am)
│   ├── backup-config.sh      # Full /config (weekly Sun 1am)
│   ├── disk-monitor.sh       # Disk space alerts
│   └── notify.sh             # Telegram helper
│
└── secrets/
    ├── .sops.yaml            # sops configuration
    └── secrets.yaml          # Encrypted secrets
```

## Storage Layout (aidan-nas)

### OS Disk (reformatted by disko)

| Disk | Size  | Model               | Purpose    |
| ---- | ----- | ------------------- | ---------- |
| sda  | 232GB | Samsung SSD 870 EVO | NixOS root |

### Data Disks (preserved, mounted by UUID)

Kernel device names on the live OMV host may shift after hotplug or reboot.
Treat the UUIDs as authoritative.

| Disk | Size | UUID                                 | Mount      |
| ---- | ---- | ------------------------------------ | ---------- |
| sdb  | 1.8T  | 48e46356-3374-4198-a5f2-fe1683b4a675 | /srv/disk1 |
| sdc  | 2.7T  | f7609add-b8af-4045-bf46-a6a4954b52ef | /srv/disk2 |
| sdd  | 1.8T  | 59990e40-4545-4024-8201-170449926f30 | /srv/disk3 |
| sde  | 3.6T  | adaa0676-75c8-4193-8663-fa170324a134 | /srv/disk4 |
| sdi  | 14.6T | c0bcf2c9-36f1-40b8-bdb0-3eeffd8f6659 | /srv/disk5 |
| sdf  | 3.6T  | 65193c76-48d3-48d8-bcee-837cf381dd47 | /srv/disk6 |
| sdg  | 3.6T  | 9287a573-8dc5-4ae8-b362-4c8c80343984 | /srv/disk7 |
| sdh  | 2.7T  | 15b064c3-da6e-4476-b141-19833c2acff9 | /srv/disk8 |

**mergerfs pool:** `/srv/disk*` -> `/srv/mergerfs/data` (~17TB)

## Services (Docker)

### Protected by Authelia (forward_auth)

- qb.aidanaden.com - qBittorrent
- qb2.aidanaden.com - qBittorrent 2
- transmission.aidanaden.com
- sonarr.aidanaden.com, sonarr-mobile.aidanaden.com
- radarr.aidanaden.com, radarr-mobile.aidanaden.com
- readarr.aidanaden.com
- jackett.aidanaden.com
- port.aidanaden.com - Portainer
- omv.aidanaden.com - OMV panel
- pihole.aidanaden.com
- kuma.aidanaden.com - Uptime Kuma

### Own Authentication (skip Authelia)

- vault.aidanaden.com - Vaultwarden
- nextcloud.aidanaden.com
- jellyfin.aidanaden.com
- photos.aidanaden.com - Immich
- books.aidanaden.com - Kavita
- linkding.aidanaden.com

### Sleepable (Sablier + Authelia)

- pdf.aidanaden.com - Stirling PDF
- cyberchef.aidanaden.com
- squoosh.aidanaden.com
- convert.aidanaden.com - ConvertX
- vert.aidanaden.com
- image.aidanaden.com - Reubah

## Backups

| Data                   | Destination            | Schedule       | Retention  |
| ---------------------- | ---------------------- | -------------- | ---------- |
| Vaultwarden + /compose | storj:backup/critical/ | Daily 2am      | 30 days    |
| /config                | storj:backup/config/   | Weekly Sun 1am | 14 days    |
| Immich photos          | storj:backup/immich/   | Daily 3am      | N/A (sync) |

## Migration Checklist

- [ ] Generate age key for sops
- [ ] Create Telegram bot (BotFather)
- [ ] Generate Authelia password hash
- [ ] Deploy backup scripts to NAS
- [ ] Test backups run successfully
- [ ] Deploy Authelia + update Caddy
- [ ] Test SSO login flow
- [ ] Build NixOS config locally
- [ ] Schedule maintenance window
- [ ] Run nixos-anywhere migration

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**

- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
