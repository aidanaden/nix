{ config, pkgs, lib, ... }:

let
  # Backup script for critical data (Vaultwarden + compose)
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
    
    [ $ERRORS -eq 0 ] && log "Backup completed successfully" || exit 1
  '';

  # Disk monitoring script
  diskMonitorScript = pkgs.writeShellScriptBin "disk-monitor" ''
    set -euo pipefail
    
    LOG="/var/log/disk-monitor.log"
    WARN_THRESHOLD=85
    CRIT_THRESHOLD=90
    
    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"; }
    
    log "========== Disk space check =========="
    
    ALERTS=""
    for fs in "/srv/mergerfs/data" "/"; do
      if ! mountpoint -q "$fs" 2>/dev/null && [ "$fs" != "/" ]; then continue; fi
      USAGE=$(df -h "$fs" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')
      AVAIL=$(df -h "$fs" 2>/dev/null | awk 'NR==2 {print $4}')
      [ -z "$USAGE" ] && continue
      log "$fs: ''${USAGE}% used ($AVAIL available)"
      if [ "$USAGE" -ge "$CRIT_THRESHOLD" ]; then
        ALERTS="$ALERTS CRITICAL: $fs at ''${USAGE}%"
      elif [ "$USAGE" -ge "$WARN_THRESHOLD" ]; then
        ALERTS="$ALERTS WARNING: $fs at ''${USAGE}%"
      fi
    done
    
    [ -z "$ALERTS" ] && log "All filesystems within normal limits" || log "$ALERTS"
    log "========== Check complete =========="
  '';

in
{
  # Install maintenance scripts
  environment.systemPackages = [
    backupCriticalScript
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

  # Backup timers
  systemd.services.backup-critical = {
    description = "Backup critical data (Vaultwarden, compose files)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupCriticalScript}/bin/backup-critical";
    };
    path = [ pkgs.docker pkgs.rclone pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
  };

  systemd.timers.backup-critical = {
    description = "Run critical backup daily at 2am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };

  systemd.services.disk-monitor = {
    description = "Check disk space";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${diskMonitorScript}/bin/disk-monitor";
    };
    path = [ pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.util-linux ];
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
