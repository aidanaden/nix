{ pkgs, terminal, ... }:
{
  programs.rofi = {
    enable = true;
    cycle = true;
    package = pkgs.rofi-wayland;
    plugins = [
      pkgs.rofi-calc
      pkgs.rofi-emoji
    ];
    terminal = "${terminal}";
    # theme = ./tokyonight.rasi;
    extraConfig = {
      modi = "drun,filebrowser,run";
      show-icons = true;
      # icon-theme = "Papirus";
      location = 0;
      font = "MesloLGS Nerd Font Mono 11";
      # font = "Monaspace Neon 11";
      drun-display-format = "{icon} {name}";
      display-drun = " Apps";
      display-run = " Run";
      display-filebrowser = " File";
    };
  };
  # xdg.configFile."rofi/tokyonight.rasi".source = ./tokyonight.rasi;
}
