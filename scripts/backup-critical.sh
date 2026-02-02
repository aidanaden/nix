#!/bin/bash
# Backup critical data to Storj
# - Vaultwarden (password manager)
# - Docker compose files
# 
# Schedule: Daily at 2am
# Retention: 30 days

set -euo pipefail

LOG="/var/log/backup-critical.log"
LOCK="/var/run/backup-critical.lock"
RCLONE_REMOTE="storj-crypt:critical"

# Paths to backup
VAULTWARDEN_DATA="/data/shared/vaultwarden"
COMPOSE_DIR="/compose"

# Retention
RETENTION_DAYS=30

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"
}

notify() {
    local status="$1"
    local message="$2"
    # Placeholder for Telegram notification
    # Will be implemented when bot is created
    if [ -x /usr/local/bin/notify.sh ]; then
        /usr/local/bin/notify.sh "$status" "$message"
    fi
}

cleanup() {
    rm -f "$LOCK"
    # Restart Vaultwarden if it was stopped
    if [ "${VAULTWARDEN_STOPPED:-false}" = "true" ]; then
        log "Restarting Vaultwarden..."
        docker start vaultwarden vaultwardendb 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
    pid=$(cat "$LOCK")
    if kill -0 "$pid" 2>/dev/null; then
        log "ERROR: Backup already running (PID $pid), skipping"
        exit 0
    fi
fi
echo $$ > "$LOCK"

log "========== Starting critical backup =========="

START_TIME=$(date +%s)
ERRORS=0

# Stop Vaultwarden for consistent backup
log "Stopping Vaultwarden for consistent backup..."
VAULTWARDEN_STOPPED=true
docker stop vaultwarden vaultwardendb 2>/dev/null || {
    log "WARNING: Could not stop Vaultwarden containers"
    VAULTWARDEN_STOPPED=false
}

# Backup Vaultwarden
log "Backing up Vaultwarden ($VAULTWARDEN_DATA)..."
if rclone sync "$VAULTWARDEN_DATA" "$RCLONE_REMOTE/vaultwarden" \
    --transfers 4 \
    --checkers 4 \
    --backup-dir "$RCLONE_REMOTE/vaultwarden-versions/$(date +%Y%m%d)" \
    -v >> "$LOG" 2>&1; then
    log "Vaultwarden backup completed"
else
    log "ERROR: Vaultwarden backup failed"
    ERRORS=$((ERRORS + 1))
fi

# Restart Vaultwarden immediately after backup
if [ "$VAULTWARDEN_STOPPED" = "true" ]; then
    log "Restarting Vaultwarden..."
    docker start vaultwardendb vaultwarden 2>/dev/null || log "WARNING: Could not restart Vaultwarden"
    VAULTWARDEN_STOPPED=false
fi

# Backup compose files
log "Backing up compose files ($COMPOSE_DIR)..."
if rclone sync "$COMPOSE_DIR" "$RCLONE_REMOTE/compose" \
    --transfers 4 \
    --checkers 4 \
    --backup-dir "$RCLONE_REMOTE/compose-versions/$(date +%Y%m%d)" \
    -v >> "$LOG" 2>&1; then
    log "Compose backup completed"
else
    log "ERROR: Compose backup failed"
    ERRORS=$((ERRORS + 1))
fi

# Cleanup old versions
log "Cleaning up versions older than $RETENTION_DAYS days..."
rclone delete "$RCLONE_REMOTE/vaultwarden-versions" --min-age "${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
rclone delete "$RCLONE_REMOTE/compose-versions" --min-age "${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
rclone rmdirs "$RCLONE_REMOTE/vaultwarden-versions" --leave-root >> "$LOG" 2>&1 || true
rclone rmdirs "$RCLONE_REMOTE/compose-versions" --leave-root >> "$LOG" 2>&1 || true

# Calculate stats
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Get backup sizes
VAULTWARDEN_SIZE=$(rclone size "$RCLONE_REMOTE/vaultwarden" --json 2>/dev/null | jq -r '.bytes // 0' | numfmt --to=iec-i 2>/dev/null || echo "unknown")
COMPOSE_SIZE=$(rclone size "$RCLONE_REMOTE/compose" --json 2>/dev/null | jq -r '.bytes // 0' | numfmt --to=iec-i 2>/dev/null || echo "unknown")

log "========== Backup Summary =========="
log "Duration: ${DURATION}s"
log "Vaultwarden size: $VAULTWARDEN_SIZE"
log "Compose size: $COMPOSE_SIZE"
log "Errors: $ERRORS"

if [ $ERRORS -eq 0 ]; then
    log "Backup completed successfully"
    notify "success" "Critical backup completed in ${DURATION}s. Vaultwarden: $VAULTWARDEN_SIZE, Compose: $COMPOSE_SIZE"
else
    log "Backup completed with $ERRORS errors"
    notify "error" "Critical backup completed with $ERRORS errors. Check logs."
    exit 1
fi
