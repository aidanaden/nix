{
  config,
  pkgs,
  ...
}: let
  yamlPython = pkgs.python3.withPackages (ps: [ps.pyyaml]);
  ensureBazarrLocalBindPy = pkgs.writeText "ensure-bazarr-local-bind.py" ''
    import pathlib
    import sys
    import yaml

    config_file = pathlib.Path(sys.argv[1])

    if config_file.exists() and config_file.stat().st_size > 0:
        with config_file.open("r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    else:
        data = {}

    general = data.setdefault("general", {})
    general["ip"] = "127.0.0.1"
    general["port"] = 6767

    with config_file.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, default_flow_style=False, sort_keys=False)
  '';

  mergerfsDeps = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };
in {
  services.bazarr = {
    enable = true;
    listenPort = 6767;
    group = "users";
  };

  # Wait for mergerfs (subtitles for media on data disks)
  systemd.services.bazarr =
    mergerfsDeps
    // {
      serviceConfig.ExecStartPre = pkgs.writeShellScript "ensure-bazarr-local-bind" ''
        set -euo pipefail

        config_dir="${config.services.bazarr.dataDir}/config"
        config_file="$config_dir/config.yaml"

        mkdir -p "$config_dir"

        ${yamlPython}/bin/python ${ensureBazarrLocalBindPy} "$config_file"
      '';
    };
}
