{ config, pkgs, ... }:

{
  # SMART monitoring for HDDs
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      # TODO: Add notification script for Telegram
      # wall.enable = true;
      # x11.enable = false;
    };
  };

  # SSD TRIM (for OS disk)
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # Automatic NixOS garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Automatic store optimization
  nix.settings.auto-optimise-store = true;

  # Periodic disk space check script
  systemd.services.disk-space-check = {
    description = "Check disk space and warn if low";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /usr/local/bin/disk-monitor.sh";
    };
  };

  systemd.timers.disk-space-check = {
    description = "Run disk space check daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Backup timers
  systemd.services.backup-critical = {
    description = "Backup critical data (Vaultwarden, compose files)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /usr/local/bin/backup-critical.sh";
    };
  };

  systemd.timers.backup-critical = {
    description = "Run critical backup daily at 2am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };

  systemd.services.backup-config = {
    description = "Backup full /config directory";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /usr/local/bin/backup-config.sh";
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
}
