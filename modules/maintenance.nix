{pkgs, ...}: let
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
    VAULTWARDEN_DATA_DOCKER="/data/shared/vaultwarden"
    VAULTWARDEN_DATA_NATIVE="/var/lib/vaultwarden"
    VAULTWARDEN_BACKUP_NATIVE="/var/backup/vaultwarden"
    COMPOSE_DIR="/compose"
    RETENTION_DAYS=30

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }

    # Back up compose definitions, not full app/user data trees.
    COMPOSE_FILTER_ARGS=(
      "--include" "global.env"
      "--include" "**/docker-compose*.yml"
      "--include" "**/docker-compose*.yaml"
      "--include" "**/compose*.yml"
      "--include" "**/compose*.yaml"
      "--include" "**/.env"
      "--include" "**/*.env"
      "--include" "**/Caddyfile"
      "--include" "**/Dockerfile"
      "--include" "**/configuration.yml"
      "--include" "**/users_database.yml"
      "--exclude" "**"
    )

    # Storj can rate-limit bursts; use conservative defaults and retries.
    RCLONE_COMMON_ARGS=(
      "--transfers" "2"
      "--checkers" "2"
      "--retries" "20"
      "--low-level-retries" "30"
      "--retries-sleep" "30s"
      "--tpslimit" "4"
      "--tpslimit-burst" "8"
      "--fast-list"
    )

    STOP_MODE="none"

    cleanup() {
      rm -f "$LOCK"
      if [ "$STOP_MODE" = "docker" ]; then
        log "Restarting Vaultwarden Docker container..."
        ${pkgs.docker}/bin/docker start vaultwarden 2>/dev/null || true
        ${pkgs.docker}/bin/docker inspect vaultwardendb >/dev/null 2>&1 && \
          ${pkgs.docker}/bin/docker start vaultwardendb 2>/dev/null || true
      elif [ "$STOP_MODE" = "systemd" ]; then
        log "Restarting Vaultwarden systemd service..."
        ${pkgs.systemd}/bin/systemctl start vaultwarden.service 2>/dev/null || true
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

    # Prefer Vaultwarden's own backup directory when available.
    if [ -d "$VAULTWARDEN_BACKUP_NATIVE" ] && [ -n "$(${pkgs.coreutils}/bin/ls -A "$VAULTWARDEN_BACKUP_NATIVE" 2>/dev/null)" ]; then
      VAULTWARDEN_DATA="$VAULTWARDEN_BACKUP_NATIVE"
      log "Using Vaultwarden native backup directory: $VAULTWARDEN_DATA"
    elif [ -d "$VAULTWARDEN_DATA_NATIVE" ]; then
      VAULTWARDEN_DATA="$VAULTWARDEN_DATA_NATIVE"
      if ${pkgs.systemd}/bin/systemctl list-unit-files vaultwarden.service >/dev/null 2>&1 && \
         ${pkgs.systemd}/bin/systemctl is-active --quiet vaultwarden.service; then
        log "Stopping Vaultwarden systemd service for consistent backup..."
        if ${pkgs.systemd}/bin/systemctl stop vaultwarden.service; then
          STOP_MODE="systemd"
        fi
      fi
    elif [ -d "$VAULTWARDEN_DATA_DOCKER" ]; then
      VAULTWARDEN_DATA="$VAULTWARDEN_DATA_DOCKER"
      if ${pkgs.docker}/bin/docker inspect vaultwarden >/dev/null 2>&1; then
        log "Stopping Vaultwarden Docker container for consistent backup..."
        ${pkgs.docker}/bin/docker stop vaultwarden >/dev/null 2>&1 || true
        ${pkgs.docker}/bin/docker inspect vaultwardendb >/dev/null 2>&1 && \
          ${pkgs.docker}/bin/docker stop vaultwardendb >/dev/null 2>&1 || true
        STOP_MODE="docker"
      fi
    else
      log "ERROR: Could not find Vaultwarden data path"
      ERRORS=$((ERRORS + 1))
      VAULTWARDEN_DATA=""
    fi

    if [ -n "$VAULTWARDEN_DATA" ]; then
      log "Backing up Vaultwarden from $VAULTWARDEN_DATA..."
      if ${pkgs.util-linux}/bin/ionice -c2 -n7 \
         ${pkgs.coreutils}/bin/nice -n 15 \
         ${pkgs.rclone}/bin/rclone sync "$VAULTWARDEN_DATA" "$RCLONE_REMOTE/vaultwarden" \
           "''${RCLONE_COMMON_ARGS[@]}" \
           --backup-dir "$RCLONE_REMOTE/vaultwarden-versions/$(date +%Y%m%d)" \
           -v >> "$LOG" 2>&1; then
        log "Vaultwarden backup completed"
      else
        log "ERROR: Vaultwarden backup failed"
        ERRORS=$((ERRORS + 1))
      fi
    fi

    if [ -d "$COMPOSE_DIR" ]; then
      log "Backing up compose definitions from $COMPOSE_DIR..."
      if ${pkgs.util-linux}/bin/ionice -c2 -n7 \
         ${pkgs.coreutils}/bin/nice -n 15 \
         ${pkgs.rclone}/bin/rclone sync "$COMPOSE_DIR" "$RCLONE_REMOTE/compose" \
           "''${RCLONE_COMMON_ARGS[@]}" \
           --max-depth "2" \
           "''${COMPOSE_FILTER_ARGS[@]}" \
           --backup-dir "$RCLONE_REMOTE/compose-versions/$(date +%Y%m%d)" \
           -v >> "$LOG" 2>&1; then
        log "Compose definitions backup completed"
      else
        log "ERROR: Compose backup failed"
        ERRORS=$((ERRORS + 1))
      fi
    else
      log "WARNING: $COMPOSE_DIR not found, skipping compose backup"
      ERRORS=$((ERRORS + 1))
    fi

    log "Cleaning up old versions..."
    ${pkgs.rclone}/bin/rclone delete "$RCLONE_REMOTE/vaultwarden-versions" --min-age "''${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
    ${pkgs.rclone}/bin/rclone delete "$RCLONE_REMOTE/compose-versions" --min-age "''${RETENTION_DAYS}d" -v >> "$LOG" 2>&1 || true
    ${pkgs.rclone}/bin/rclone rmdirs "$RCLONE_REMOTE/vaultwarden-versions" --leave-root >> "$LOG" 2>&1 || true
    ${pkgs.rclone}/bin/rclone rmdirs "$RCLONE_REMOTE/compose-versions" --leave-root >> "$LOG" 2>&1 || true

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

    RCLONE_COMMON_ARGS=(
      "--transfers" "2"
      "--checkers" "2"
      "--retries" "20"
      "--low-level-retries" "30"
      "--retries-sleep" "30s"
      "--tpslimit" "4"
      "--tpslimit-burst" "8"
      "--fast-list"
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
    if [ ! -d "$CONFIG_DIR" ]; then
      log "ERROR: $CONFIG_DIR not found"
      ${notifyScript}/bin/notify error "Config backup failed: $CONFIG_DIR not found"
      exit 1
    fi

    if ${pkgs.util-linux}/bin/ionice -c2 -n7 \
       ${pkgs.coreutils}/bin/nice -n 15 \
       ${pkgs.rclone}/bin/rclone sync "$CONFIG_DIR" "$RCLONE_REMOTE/latest" \
         "''${RCLONE_COMMON_ARGS[@]}" \
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

    RCLONE_COMMON_ARGS=(
      "--transfers" "2"
      "--checkers" "2"
      "--retries" "20"
      "--low-level-retries" "30"
      "--retries-sleep" "30s"
      "--tpslimit" "4"
      "--tpslimit-burst" "8"
      "--fast-list"
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

    log "========== Starting Immich backup =========="
    START_TIME=$(date +%s)

    if [ ! -d "$IMMICH_DATA" ]; then
      log "ERROR: Immich data directory not found at $IMMICH_DATA"
      ${notifyScript}/bin/notify error "Immich backup failed: $IMMICH_DATA not found"
      exit 1
    fi

    log "Syncing Immich data to storj..."
    if ${pkgs.util-linux}/bin/ionice -c2 -n7 \
       ${pkgs.coreutils}/bin/nice -n 15 \
       ${pkgs.rclone}/bin/rclone sync "$IMMICH_DATA" "$RCLONE_REMOTE" \
         "''${RCLONE_COMMON_ARGS[@]}" \
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

  mkBackupService = {
    description,
    script,
    path,
  }: {
    inherit description;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.util-linux}/bin/flock -w 21600 /var/run/backup-global.lock ${script}";
      Nice = 15;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
    };
    path = path ++ [pkgs.util-linux];
  };

  mkTimer = {
    description,
    onCalendar,
  }: {
    inherit description;
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = onCalendar;
      Persistent = true;
      RandomizedDelaySec = "10m";
      AccuracySec = "1m";
    };
  };
in {
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

  systemd.services.backup-critical = mkBackupService {
    description = "Backup critical data (Vaultwarden, compose files)";
    script = "${backupCriticalScript}/bin/backup-critical";
    path = [pkgs.docker pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.curl];
  };

  systemd.services.backup-config = mkBackupService {
    description = "Backup /config directory to Storj";
    script = "${backupConfigScript}/bin/backup-config";
    path = [pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.jq pkgs.curl];
  };

  systemd.services.immich-backup = mkBackupService {
    description = "Backup Immich photos to Storj";
    script = "${immichBackupScript}/bin/immich-backup";
    path = [pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.curl];
  };

  systemd.services.disk-monitor = {
    description = "Check disk space and send alerts";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${diskMonitorScript}/bin/disk-monitor";
    };
    path = [pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.util-linux pkgs.curl];
  };

  # ===== Systemd timers =====

  systemd.timers.backup-critical = mkTimer {
    description = "Run critical backup daily at 2am";
    onCalendar = "*-*-* 02:00:00";
  };

  systemd.timers.backup-config = mkTimer {
    description = "Run config backup weekly on Sunday at 1am";
    onCalendar = "Sun *-*-* 01:00:00";
  };

  systemd.timers.immich-backup = mkTimer {
    description = "Run Immich backup daily at 3am";
    onCalendar = "*-*-* 03:00:00";
  };

  systemd.timers.disk-monitor = mkTimer {
    description = "Run disk space check daily at 6am";
    onCalendar = "*-*-* 06:00:00";
  };
}
