# NixOS Migration Runbook - aidan-nas

## Pre-Migration Checklist

- [ ] Verify backups are recent (storj-crypt)
- [ ] Note down current Tailscale IP: `100.92.143.10`
- [ ] Ensure you have LAN access: `192.168.0.69` (fallback if Tailscale breaks)
- [ ] Have age private key ready (in macOS Keychain or Vaultwarden)

## Backup Verification

```bash
# SSH to NAS and check last backup
ssh aidan@100.92.143.10 "ls -la /var/log/backup-*.log 2>/dev/null || echo 'Check cron logs'"

# Or run manual backup
ssh aidan@100.92.143.10 "sudo /usr/local/bin/backup-critical.sh"
```

## Migration Steps

### 1. Export age key to temp file

```bash
# On your Mac
security find-generic-password -a 'sops-age' -s 'sops-age-key' -w > /tmp/age-key.txt
chmod 600 /tmp/age-key.txt

# Verify
cat /tmp/age-key.txt
# Should show: AGE-SECRET-KEY-...
```

### 2. Prepare extra files for deployment

Create directory structure for files that need to be copied:

```bash
mkdir -p /tmp/nixos-extra/var/lib/sops-nix
cp /tmp/age-key.txt /tmp/nixos-extra/var/lib/sops-nix/key.txt
chmod 600 /tmp/nixos-extra/var/lib/sops-nix/key.txt
```

### 3. Run nixos-anywhere

```bash
cd ~/projects/nixos-machines

# Dry-run first (shows what would happen)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#aidan-nas \
  --extra-files /tmp/nixos-extra \
  --dry-run \
  root@192.168.0.69

# If dry-run looks good, run for real
nix run github:nix-community/nixos-anywhere -- \
  --flake .#aidan-nas \
  --extra-files /tmp/nixos-extra \
  root@192.168.0.69
```

**Important:** Use LAN IP (`192.168.0.69`) not Tailscale IP, since Tailscale will be reconfigured.

### 4. Wait for installation

- Takes ~10-15 minutes
- NAS will reboot automatically
- Watch for SSH to come back up

### 5. Clean up temp files

```bash
rm -f /tmp/age-key.txt
rm -rf /tmp/nixos-extra
```

## Post-Migration Verification

### 1. SSH into new system

```bash
# Try Tailscale first (should auto-connect with auth key)
ssh aidan@100.92.143.10

# Or use LAN IP
ssh aidan@192.168.0.69
```

### 2. Verify services

```bash
# Check system status
systemctl status

# Check Tailscale
tailscale status

# Check Docker
docker ps

# Check mergerfs mount
df -h /srv/mergerfs/data

# Check data disks
ls -la /srv/disk*/

# Check sops secrets were decrypted
ls -la /run/secrets/
cat /root/.config/rclone/rclone.conf | head -5

# Test rclone
rclone ls storj-crypt: | head -10
```

### 3. Start Docker services

```bash
# Navigate to compose directory
cd /compose  # or /data/compose

# Start services (adjust path as needed)
docker compose -f caddy/docker-compose.yml up -d
docker compose -f immich/docker-compose.yml up -d
# ... etc
```

### 4. Verify external access

- [ ] Check `vault.aidanaden.com` loads
- [ ] Check `jellyfin.aidanaden.com` loads
- [ ] Check `photos.aidanaden.com` loads

## Rollback Plan

If something goes catastrophically wrong:

1. **Data is safe** - All data disks (sdb-sdi) are untouched by disko
2. **Boot from USB** - Use NixOS or Debian live USB
3. **Mount data disks** - `/dev/sdb1`, etc. still have all your data
4. **Reinstall OMV** - If needed, reinstall OMV on `/dev/sda`

## Troubleshooting

### Tailscale not connecting

```bash
# Check if auth key was used
journalctl -u tailscaled -n 50

# Manual auth if needed
sudo tailscale up --auth-key=tskey-auth-...
```

### Secrets not decrypting

```bash
# Check age key exists
ls -la /var/lib/sops-nix/key.txt

# Check sops-nix status
systemctl status sops-nix

# Manual decrypt test
SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops -d /etc/nixos/secrets/secrets.yaml
```

### Data disks not mounting

```bash
# Check disk UUIDs
blkid

# Compare with expected UUIDs in filesystems.nix
# Manually mount if needed
mount /dev/sdb1 /srv/disk1
```

### mergerfs not starting

```bash
# Check service status
systemctl status mergerfs

# Manual start
mergerfs /srv/disk1:/srv/disk2:/srv/disk3:/srv/disk4:/srv/disk5:/srv/disk6:/srv/disk7:/srv/disk8 \
  /srv/mergerfs/data \
  -o defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs
```

## Reference

- **Tailscale IP:** 100.92.143.10
- **LAN IP:** 192.168.0.69
- **Age public key:** age15n3l3w3xhvxhrplaggmtjgnwqdvs9xy08lptz9kl3f5rnjzgagesy585pe
- **Flake:** `~/projects/nixos-machines#aidan-nas`
