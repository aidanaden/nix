{
  pkgs,
  pkgs-unstable,
  ...
}: let
  unstable = pkgs-unstable;
  chromeCdp = pkgs.writeShellScriptBin "chrome-cdp" ''
    set -euo pipefail

    port="9222"
    if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
      port="$1"
      shift
    fi

    profile_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/chrome-cdp-$port"
    mkdir -p "$profile_dir"

    exec /usr/bin/open -na "Google Chrome" --args \
      --remote-debugging-port="$port" \
      --user-data-dir="$profile_dir" \
      "$@"
  '';
in {
  home.packages = [
    unstable.google-chrome
    chromeCdp
  ];
}
