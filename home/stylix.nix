{ pkgs, ... }:
{
  stylix = {
    enable = true;
    autoEnable = true;
    overlays.enable = false;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";
    image = ../wallpapers/tokyodark/wallpaper1.png;
    polarity = "dark";
    targets = {
      kitty = {
        enable = true;
        variant256Colors = true;
      };
      waybar = {
        enable = true;
        enableCenterBackColors = false;
        enableLeftBackColors = false;
        enableRightBackColors = false;
      };
      neovim = {
        enable = false;
      };
      # rofi = {
      #   enable = true;
      # };
      # hyprland = {
      #   enable = true;
      # };
      # tmux = {
      #   enable = true;
      # };
      # spicetify = {
      #   enable = true;
      # };
    };

    opacity = {
      desktop = 1.0;
      popups = 1.0;
      applications = 1.0;
      terminal = 1.0;
    };

    fonts = {
      sizes = {
        desktop = 12;
        popups = 11;
        terminal = 11;
        applications = 12;
      };

      serif = {
        package = pkgs.meslo-lgs-nf;
        name = "MesloLGS Nerd Font Mono";
        # package = pkgs.monaspace;
        # name = "Monaspace Neon";
      };
      sansSerif = {
        package = pkgs.meslo-lgs-nf;
        name = "MesloLGS Nerd Font Mono";
        # package = pkgs.monaspace;
        # name = "Monaspace Neon";
      };
      monospace = {
        package = pkgs.meslo-lgs-nf;
        name = "MesloLGS Nerd Font Mono";
        # package = pkgs.monaspace;
        # name = "Monaspace Neon";
      };
      emoji = {
        package = pkgs.meslo-lgs-nf;
        name = "MesloLGS Nerd Font Mono";
        # package = pkgs.monaspace;
        # name = "Monaspace Neon";
      };
    };
  };
}
