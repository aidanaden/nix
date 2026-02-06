{ config, pkgs, lib, ... }:

let
  # Upgrade notification scripts (use notifyScript from maintenance.nix via PATH)
  notifyUpgradeSuccess = pkgs.writeShellScript "notify-upgrade-success" ''
    set -euo pipefail
    HOSTNAME=$(${pkgs.hostname}/bin/hostname)
    TOKEN_FILE="/run/secrets/telegram_bot_token"
    CHAT_ID_FILE="/run/secrets/telegram_chat_id"
    [ ! -f "$TOKEN_FILE" ] || [ ! -f "$CHAT_ID_FILE" ] && exit 0
    TOKEN=$(cat "$TOKEN_FILE")
    CHAT_ID=$(cat "$CHAT_ID_FILE")
    [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ] && exit 0
    GENERATION=$(readlink /nix/var/nix/profiles/system | sed 's/.*-//')
    MSG="✅ *[$HOSTNAME]* NixOS upgrade succeeded

Generation: $GENERATION
Staged as boot default. Reboot to activate.

_$(date '+%Y-%m-%d %H:%M:%S')_"
    ${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot''${TOKEN}/sendMessage" \
      -d "chat_id=''${CHAT_ID}" \
      -d "text=''${MSG}" \
      -d "parse_mode=Markdown" \
      -d "disable_web_page_preview=true" > /dev/null
  '';

  notifyUpgradeFailure = pkgs.writeShellScript "notify-upgrade-failure" ''
    set -euo pipefail
    HOSTNAME=$(${pkgs.hostname}/bin/hostname)
    TOKEN_FILE="/run/secrets/telegram_bot_token"
    CHAT_ID_FILE="/run/secrets/telegram_chat_id"
    [ ! -f "$TOKEN_FILE" ] || [ ! -f "$CHAT_ID_FILE" ] && exit 0
    TOKEN=$(cat "$TOKEN_FILE")
    CHAT_ID=$(cat "$CHAT_ID_FILE")
    [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ] && exit 0
    MSG="❌ *[$HOSTNAME]* NixOS upgrade FAILED

Check logs: journalctl -u nixos-upgrade.service

_$(date '+%Y-%m-%d %H:%M:%S')_"
    ${pkgs.curl}/bin/curl -s -X POST "https://api.telegram.org/bot''${TOKEN}/sendMessage" \
      -d "chat_id=''${CHAT_ID}" \
      -d "text=''${MSG}" \
      -d "parse_mode=Markdown" \
      -d "disable_web_page_preview=true" > /dev/null
  '';

in
{
  system.autoUpgrade = {
    enable = true;

    # TODO: Update to actual GitHub repo URL once remote is set up
    # The NAS will pull this repo and rebuild using the committed flake.lock.
    # To update nixpkgs: run `nix flake update` locally, test, push.
    flake = "github:aidanaden/nixos-machines#aidan-nas";

    # Stage as boot default only — don't restart running services
    operation = "boot";

    # Check for updates daily at 4am (with up to 45min jitter)
    dates = "04:00";
    randomizedDelaySec = "45min";

    # Auto-reboot only within safe window (5-6am)
    allowReboot = true;
    rebootWindow = {
      lower = "05:00";
      upper = "06:00";
    };

    # If NAS was off at scheduled time, run on next boot
    persistent = true;

    flags = [
      "--print-build-logs"
    ];
  };

  # Notify on upgrade success/failure via Telegram
  systemd.services.notify-upgrade-success = {
    description = "Notify on successful NixOS upgrade";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = notifyUpgradeSuccess;
    };
    path = [ pkgs.coreutils pkgs.curl ];
  };

  systemd.services.notify-upgrade-failure = {
    description = "Notify on failed NixOS upgrade";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = notifyUpgradeFailure;
    };
    path = [ pkgs.coreutils pkgs.curl ];
  };

  systemd.services.nixos-upgrade = {
    onSuccess = [ "notify-upgrade-success.service" ];
    onFailure = [ "notify-upgrade-failure.service" ];
  };
}
