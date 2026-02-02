#!/bin/bash
# Monitor disk space and send alerts
# 
# Schedule: Daily
# Thresholds: 85% warning, 90% critical

set -euo pipefail

LOG="/var/log/disk-monitor.log"

# Thresholds (percentage)
WARN_THRESHOLD=85
CRIT_THRESHOLD=90

# Filesystems to monitor
FILESYSTEMS=(
    "/srv/mergerfs/data"
    "/"
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

log "========== Disk space check =========="

ALERTS=""
ALERT_LEVEL="info"

for fs in "${FILESYSTEMS[@]}"; do
    if ! mountpoint -q "$fs" 2>/dev/null && [ "$fs" != "/" ]; then
        log "WARNING: $fs is not mounted, skipping"
        continue
    fi
    
    # Get usage percentage (remove % sign)
    USAGE=$(df -h "$fs" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
    AVAIL=$(df -h "$fs" 2>/dev/null | awk 'NR==2 {print $4}')
    TOTAL=$(df -h "$fs" 2>/dev/null | awk 'NR==2 {print $2}')
    
    if [ -z "$USAGE" ]; then
        log "ERROR: Could not get usage for $fs"
        continue
    fi
    
    log "$fs: ${USAGE}% used ($AVAIL available of $TOTAL)"
    
    if [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
        ALERTS="$ALERTS\nCRITICAL: $fs is ${USAGE}% full ($AVAIL free)"
        ALERT_LEVEL="critical"
    elif [ "$USAGE" -ge "$WARN_THRESHOLD" ]; then
        ALERTS="$ALERTS\nWARNING: $fs is ${USAGE}% full ($AVAIL free)"
        if [ "$ALERT_LEVEL" != "critical" ]; then
            ALERT_LEVEL="warning"
        fi
    fi
done

# Check individual data disks
for i in {1..8}; do
    disk="/srv/disk$i"
    if mountpoint -q "$disk" 2>/dev/null; then
        USAGE=$(df -h "$disk" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
        AVAIL=$(df -h "$disk" 2>/dev/null | awk 'NR==2 {print $4}')
        
        if [ -n "$USAGE" ] && [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
            log "CRITICAL: $disk is ${USAGE}% full ($AVAIL free)"
            ALERTS="$ALERTS\nCRITICAL: $disk is ${USAGE}% full"
            ALERT_LEVEL="critical"
        fi
    fi
done

# Send notification if there are alerts
if [ -n "$ALERTS" ]; then
    log "Sending $ALERT_LEVEL alert..."
    if [ "$ALERT_LEVEL" = "critical" ]; then
        notify "error" "Disk space CRITICAL:$ALERTS"
    else
        notify "warning" "Disk space warning:$ALERTS"
    fi
else
    log "All filesystems within normal limits"
fi

log "========== Check complete =========="
