#!/bin/bash
# Backup full /config directory to Storj
# 
# Schedule: Weekly on Sunday at 1am
# Retention: 14 days

set -euo pipefail

LOG="/var/log/backup-config.log"
LOCK="/var/run/backup-config.lock"
RCLONE_REMOTE="storj:backup/config"

# Path to backup
CONFIG_DIR="/config"

# Retention
RETENTION_DAYS=14

# Excludes (caches, temp files, etc.)
EXCLUDES=(
    "**/.cache/**"
    "**/cache/**"
    "**/Cache/**"
    "**/*.log"
    "**/*.tmp"
    "**/transcodes/**"
    "**/metadata/People/**"
    "**/linuxserver-jellyfin/data/metadata/**"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"
}

notify() {
    local status="$1"
    local message="$2"
    if [ -x /usr/local/bin/notify.sh ]; then
        /usr/local/bin/notify.sh "$status" "$message"
    fi
}

# Prevent concurrent runs
if [ -f "$LOCK" ]; then
    pid=$(cat "$LOCK")
    if kill -0 "$pid" 2>/dev/null; then
        log "ERROR: Backup already running (PID $pid), skipping"
        exit 0
    fi
fi
echo $$ > "$LOCK"
trap "rm -f $LOCK" EXIT

log "========== Starting config backup =========="

START_TIME=$(date +%s)

# Build exclude arguments
EXCLUDE_ARGS=""
for pattern in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude '$pattern'"
done

# Backup config
log "Backing up config ($CONFIG_DIR)..."
if eval rclone sync "$CONFIG_DIR" "$RCLONE_REMOTE/latest" \
    --transfers 4 \
    --checkers 4 \
    --backup-dir "$RCLONE_REMOTE/versions/$(date +%Y%m%d)" \
    $EXCLUDE_ARGS \
    -v >> "$LOG" 2>&1; then
    log "Config backup completed"
else
    log "ERROR: Config backup failed"
    notify "error" "Config backup failed. Check logs."
    exit 1
fi

# Cleanup old versions
log "Cleaning up versions older than $RETENTION_DAYS days..."
rclone delete "$RCLONE_REMOTE/versions" --min-age "${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
rclone rmdirs "$RCLONE_REMOTE/versions" --leave-root >> "$LOG" 2>&1 || true

# Calculate stats
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Get backup size
CONFIG_SIZE=$(rclone size "$RCLONE_REMOTE/latest" --json 2>/dev/null | jq -r '.bytes // 0' | numfmt --to=iec-i 2>/dev/null || echo "unknown")
FILE_COUNT=$(rclone size "$RCLONE_REMOTE/latest" --json 2>/dev/null | jq -r '.count // 0' || echo "unknown")

log "========== Backup Summary =========="
log "Duration: ${DURATION}s"
log "Config size: $CONFIG_SIZE ($FILE_COUNT files)"

log "Backup completed successfully"
notify "success" "Config backup completed in ${DURATION}s. Size: $CONFIG_SIZE ($FILE_COUNT files)"
