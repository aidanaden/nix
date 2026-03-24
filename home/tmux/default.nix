{
  pkgs,
  lib,
  pkgs-unstable,
  terminal,
  ...
}: let
  unstable = pkgs-unstable;
  sessionx = pkgs.tmuxPlugins.tmux-sessionx.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace scripts/sessionx.sh \
          --replace-fail "paths=\$(find \''${clean_paths//,/ } -mindepth 1 -maxdepth 1 -type d)" "paths=\"\''${clean_paths//,/ } \$(find \''${clean_paths//,/ } -mindepth 1 -maxdepth 1 -type d -not -name '.*')\""
      '';
  });
in {
  programs.tmux = {
    enable = true;
    shortcut = "b";
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 10000;
    keyMode = "vi";
    shell = "${pkgs.zsh}/bin/zsh";
    "terminal" =
      if terminal == "alacritty"
      then "alacritty"
      else "xterm-kitty";

    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'off'
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '60'
        '';
      }
      {
        plugin = sessionx;
        extraConfig = ''
          set -g @sessionx-bind 'T'
          set -g @sessionx-custom-paths '/Users/aidan/projects,/Users/aidan/jupiter,/Users/aidan/research,/Users/aidan/dotfiles'
          set -g @sessionx-custom-paths-subdirectories 'true'
          set -g @sessionx-layout 'reverse'
        '';
      }
      tmuxPlugins.better-mouse-mode
      # {
      #   plugin = unstable.tmuxPlugins.catppuccin;
      #   extraConfig = ''
      #     set -g @catppuccin_flavor 'mocha' # latte, frappe, macchiato or mocha
      #   '';
      # }
      {
        plugin = unstable.tmuxPlugins.tokyo-night-tmux;
        extraConfig = ''
          set -g @tokyo-night-tmux_window_id_style digital
          set -g @tokyo-night-tmux_pane_id_style hsquare
          set -g @tokyo-night-tmux_zoom_id_style dsquare

          set -g @tokyo-night-tmux_show_path 1
          set -g @tokyo-night-tmux_path_format relative # 'relative' or 'full'

          set -g @tokyo-night-tmux_show_git 0
          set -g @tokyo-night-tmux_show_netspeed 0
        '';
      }
    ];

    extraConfig = lib.strings.fileContents ./tmux.conf;
  };
}
