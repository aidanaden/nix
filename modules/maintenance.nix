{ config, pkgs, lib, ... }:

let
  # Telegram notification helper
  # Requires sops secrets: telegram_bot_token, telegram_chat_id
  notifyScript = pkgs.writeShellScriptBin "notify" ''
    set -euo pipefail

    STATUS="''${1:-info}"
    MESSAGE="''${2:-No message provided}"
    HOSTNAME=$(${pkgs.hostname}/bin/hostname)

    # Read secrets from sops-nix paths
    TOKEN_FILE="/run/secrets/telegram_bot_token"
    CHAT_ID_FILE="/run/secrets/telegram_chat_id"

    if [ ! -f "$TOKEN_FILE" ] || [ ! -f "$CHAT_ID_FILE" ]; then
      echo "WARNING: Telegram not configured (missing sops secrets). Message: [$STATUS] $MESSAGE"
      exit 0
    fi

    TOKEN=$(cat "$TOKEN_FILE")
    CHAT_ID=$(cat "$CHAT_ID_FILE")

    if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
      echo "WARNING: Telegram secrets empty. Message: [$STATUS] $MESSAGE"
      exit 0
    fi

    # Status icons
    case "$STATUS" in
      success) ICON="✅" ;;
      error)   ICON="❌" ;;
      warning) ICON="⚠️" ;;
      *)       ICON="ℹ️" ;;
    esac

    FORMATTED="$ICON *[$HOSTNAME]* $STATUS

$MESSAGE

_$(date '+%Y-%m-%d %H:%M:%S')_"

    response=$(${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot''${TOKEN}/sendMessage" \
      -d "chat_id=''${CHAT_ID}" \
      -d "text=''${FORMATTED}" \
      -d "parse_mode=Markdown" \
      -d "disable_web_page_preview=true")

    if echo "$response" | ${pkgs.gnugrep}/bin/grep -q '"ok":true'; then
      echo "Notification sent"
    else
      echo "ERROR: Failed to send notification: $response"
      exit 1
    fi
  '';

  # Backup critical data (Vaultwarden + compose files)
  backupCriticalScript = pkgs.writeShellScriptBin "backup-critical" ''
    set -euo pipefail

    LOG="/var/log/backup-critical.log"
    LOCK="/var/run/backup-critical.lock"
    RCLONE_REMOTE="storj-crypt:critical"
    VAULTWARDEN_DATA="/data/shared/vaultwarden"
    COMPOSE_DIR="/compose"
    RETENTION_DAYS=30

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

    cleanup() {
      rm -f "$LOCK"
      if [ "''${VAULTWARDEN_STOPPED:-false}" = "true" ]; then
        log "Restarting Vaultwarden..."
        ${pkgs.docker}/bin/docker start vaultwardendb vaultwarden 2>/dev/null || true
      fi
    }
    trap cleanup EXIT

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

    log "Stopping Vaultwarden..."
    VAULTWARDEN_STOPPED=true
    ${pkgs.docker}/bin/docker stop vaultwarden vaultwardendb 2>/dev/null || VAULTWARDEN_STOPPED=false

    log "Backing up Vaultwarden..."
    if ${pkgs.rclone}/bin/rclone sync "$VAULTWARDEN_DATA" "$RCLONE_REMOTE/vaultwarden" \
        --transfers 4 --checkers 4 \
        --backup-dir "$RCLONE_REMOTE/vaultwarden-versions/$(date +%Y%m%d)" \
        -v >> "$LOG" 2>&1; then
      log "Vaultwarden backup completed"
    else
      log "ERROR: Vaultwarden backup failed"
      ERRORS=$((ERRORS + 1))
    fi

    if [ "$VAULTWARDEN_STOPPED" = "true" ]; then
      log "Restarting Vaultwarden..."
      ${pkgs.docker}/bin/docker start vaultwardendb vaultwarden 2>/dev/null || true
      VAULTWARDEN_STOPPED=false
    fi

    log "Backing up compose files..."
    if ${pkgs.rclone}/bin/rclone sync "$COMPOSE_DIR" "$RCLONE_REMOTE/compose" \
        --transfers 4 --checkers 4 \
        --backup-dir "$RCLONE_REMOTE/compose-versions/$(date +%Y%m%d)" \
        -v >> "$LOG" 2>&1; then
      log "Compose backup completed"
    else
      log "ERROR: Compose backup failed"
      ERRORS=$((ERRORS + 1))
    fi

    log "Cleaning up old versions..."
    ${pkgs.rclone}/bin/rclone delete "$RCLONE_REMOTE/vaultwarden-versions" --min-age "''${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
    ${pkgs.rclone}/bin/rclone delete "$RCLONE_REMOTE/compose-versions" --min-age "''${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    log "========== Backup Summary =========="
    log "Duration: ''${DURATION}s, Errors: $ERRORS"

    if [ $ERRORS -eq 0 ]; then
      log "Backup completed successfully"
      ${notifyScript}/bin/notify success "Critical backup completed in ''${DURATION}s"
    else
      log "Backup completed with $ERRORS errors"
      ${notifyScript}/bin/notify error "Critical backup had $ERRORS errors. Check /var/log/backup-critical.log"
      exit 1
    fi
  '';

  # Backup /config directory
  backupConfigScript = pkgs.writeShellScriptBin "backup-config" ''
    set -euo pipefail

    LOG="/var/log/backup-config.log"
    LOCK="/var/run/backup-config.lock"
    RCLONE_REMOTE="storj-crypt:config"
    CONFIG_DIR="/config"
    RETENTION_DAYS=14

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

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

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

    # Build exclude arguments as proper array
    EXCLUDE_ARGS=()
    for pattern in "''${EXCLUDES[@]}"; do
      EXCLUDE_ARGS+=("--exclude" "$pattern")
    done

    log "Backing up config ($CONFIG_DIR)..."
    if ${pkgs.rclone}/bin/rclone sync "$CONFIG_DIR" "$RCLONE_REMOTE/latest" \
        --transfers 4 --checkers 4 \
        --backup-dir "$RCLONE_REMOTE/versions/$(date +%Y%m%d)" \
        "''${EXCLUDE_ARGS[@]}" \
        -v >> "$LOG" 2>&1; then
      log "Config backup completed"
    else
      log "ERROR: Config backup failed"
      ${notifyScript}/bin/notify error "Config backup failed. Check /var/log/backup-config.log"
      exit 1
    fi

    log "Cleaning up versions older than $RETENTION_DAYS days..."
    ${pkgs.rclone}/bin/rclone delete "$RCLONE_REMOTE/versions" --min-age "''${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
    ${pkgs.rclone}/bin/rclone rmdirs "$RCLONE_REMOTE/versions" --leave-root >> "$LOG" 2>&1 || true

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    CONFIG_SIZE=$(${pkgs.rclone}/bin/rclone size "$RCLONE_REMOTE/latest" --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.bytes // 0' | ${pkgs.coreutils}/bin/numfmt --to=iec-i 2>/dev/null || echo "unknown")
    FILE_COUNT=$(${pkgs.rclone}/bin/rclone size "$RCLONE_REMOTE/latest" --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.count // 0' || echo "unknown")

    log "========== Backup Summary =========="
    log "Duration: ''${DURATION}s, Size: $CONFIG_SIZE ($FILE_COUNT files)"
    log "Backup completed successfully"

    ${notifyScript}/bin/notify success "Config backup completed in ''${DURATION}s. Size: $CONFIG_SIZE ($FILE_COUNT files)"
  '';

  # Backup Immich data
  immichBackupScript = pkgs.writeShellScriptBin "immich-backup" ''
    set -euo pipefail

    LOG="/var/log/immich-backup.log"
    LOCK="/var/run/immich-backup.lock"
    RCLONE_REMOTE="storj-crypt:immich"
    IMMICH_DATA="/data/shared/immich"

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

    if [ -f "$LOCK" ]; then
      pid=$(cat "$LOCK")
      if kill -0 "$pid" 2>/dev/null; then
        log "ERROR: Backup already running (PID $pid), skipping"
        exit 0
      fi
    fi
    echo $$ > "$LOCK"
    trap "rm -f $LOCK" EXIT

    log "========== Starting Immich backup =========="
    START_TIME=$(date +%s)

    if [ ! -d "$IMMICH_DATA" ]; then
      log "ERROR: Immich data directory not found at $IMMICH_DATA"
      ${notifyScript}/bin/notify error "Immich backup failed: $IMMICH_DATA not found"
      exit 1
    fi

    log "Syncing Immich data to storj..."
    if ${pkgs.rclone}/bin/rclone sync "$IMMICH_DATA" "$RCLONE_REMOTE" \
        --transfers 4 --checkers 8 \
        --exclude "**/.cache/**" \
        --exclude "**/thumbs/**" \
        --exclude "**/encoded-video/**" \
        -v >> "$LOG" 2>&1; then
      log "Immich sync completed"
    else
      log "ERROR: Immich sync failed"
      ${notifyScript}/bin/notify error "Immich backup failed. Check /var/log/immich-backup.log"
      exit 1
    fi

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    log "========== Backup Summary =========="
    log "Duration: ''${DURATION}s"
    log "Immich backup completed successfully"

    ${notifyScript}/bin/notify success "Immich backup completed in ''${DURATION}s"
  '';

  # Disk monitoring
  diskMonitorScript = pkgs.writeShellScriptBin "disk-monitor" ''
    set -euo pipefail

    LOG="/var/log/disk-monitor.log"
    WARN_THRESHOLD=85
    CRIT_THRESHOLD=90

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

    log "========== Disk space check =========="

    ALERTS=""
    ALERT_LEVEL="info"

    for fs in "/srv/mergerfs/data" "/"; do
      if ! mountpoint -q "$fs" 2>/dev/null && [ "$fs" != "/" ]; then
        log "WARNING: $fs is not mounted, skipping"
        continue
      fi
      USAGE=$(df -h "$fs" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $5}' | tr -d '%')
      AVAIL=$(df -h "$fs" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}')
      TOTAL=$(df -h "$fs" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $2}')
      [ -z "$USAGE" ] && continue
      log "$fs: ''${USAGE}% used ($AVAIL available of $TOTAL)"
      if [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
        ALERTS="$ALERTS
CRITICAL: $fs is ''${USAGE}% full ($AVAIL free)"
        ALERT_LEVEL="critical"
      elif [ "$USAGE" -ge "$WARN_THRESHOLD" ]; then
        ALERTS="$ALERTS
WARNING: $fs is ''${USAGE}% full ($AVAIL free)"
        if [ "$ALERT_LEVEL" != "critical" ]; then
          ALERT_LEVEL="warning"
        fi
      fi
    done

    # Check individual data disks
    for i in $(seq 1 8); do
      disk="/srv/disk$i"
      if mountpoint -q "$disk" 2>/dev/null; then
        USAGE=$(df -h "$disk" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $5}' | tr -d '%')
        AVAIL=$(df -h "$disk" 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR==2 {print $4}')
        if [ -n "$USAGE" ] && [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
          log "CRITICAL: $disk is ''${USAGE}% full ($AVAIL free)"
          ALERTS="$ALERTS
CRITICAL: $disk is ''${USAGE}% full"
          ALERT_LEVEL="critical"
        fi
      fi
    done

    if [ -n "$ALERTS" ]; then
      log "Sending $ALERT_LEVEL alert..."
      if [ "$ALERT_LEVEL" = "critical" ]; then
        ${notifyScript}/bin/notify error "Disk space CRITICAL:$ALERTS"
      else
        ${notifyScript}/bin/notify warning "Disk space warning:$ALERTS"
      fi
    else
      log "All filesystems within normal limits"
    fi

    log "========== Check complete =========="
  '';

in
{
  # Install maintenance scripts
  environment.systemPackages = [
    notifyScript
    backupCriticalScript
    backupConfigScript
    immichBackupScript
    diskMonitorScript
  ];

  # SMART monitoring for HDDs
  services.smartd = {
    enable = true;
    autodetect = true;
  };

  # SSD TRIM (for OS disk)
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # Nix garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.settings.auto-optimise-store = true;

  # ===== Systemd services =====

  systemd.services.backup-critical = {
    description = "Backup critical data (Vaultwarden, compose files)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupCriticalScript}/bin/backup-critical";
    };
    path = [ pkgs.docker pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.curl ];
  };

  systemd.services.backup-config = {
    description = "Backup /config directory to Storj";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupConfigScript}/bin/backup-config";
    };
    path = [ pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.jq pkgs.curl ];
  };

  systemd.services.immich-backup = {
    description = "Backup Immich photos to Storj";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${immichBackupScript}/bin/immich-backup";
    };
    path = [ pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.curl ];
  };

  systemd.services.disk-monitor = {
    description = "Check disk space and send alerts";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${diskMonitorScript}/bin/disk-monitor";
    };
    path = [ pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.util-linux pkgs.curl ];
  };

  # ===== Systemd timers =====

  systemd.timers.backup-critical = {
    description = "Run critical backup daily at 2am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };

  systemd.timers.backup-config = {
    description = "Run config backup weekly on Sunday at 1am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 01:00:00";
      Persistent = true;
    };
  };

  systemd.timers.immich-backup = {
    description = "Run Immich backup daily at 3am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
    };
  };

  systemd.timers.disk-monitor = {
    description = "Run disk space check daily at 6am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      Persistent = true;
    };
  };
}
