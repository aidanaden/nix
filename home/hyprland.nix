{
  pkgs,
  lib,
  pkgs-unstable,
  scale,
  terminal,
  ...
}:
let
  unstable = pkgs-unstable;
in
{
  home.packages = with pkgs; [
    brightnessctl # Screen brightness daemon
    swww # Wallpaper daemon
    libnotify # Notification libraries
    grim # Screenshots
    slurp # Screenshots
    udiskie # Automatic device mounting
    xdg-utils # Utilities for better X/Wayland integration
    # wlogout # Logout/shutdown/hibernate/lock screen modal UI
    font-awesome # Fonts
    wl-clipboard # Clipboard
    playerctl # Media player daemon
    networkmanagerapplet
    lshw
    qt5.qtwayland
    qt6.qtwayland
  ];

  # XDG portal
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal
    ];
    configPackages = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal
    ];
  };

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    xwayland.enable = true;

    settings = {
      "$terminal" = "${terminal}";
      "$mod" = "SUPER";

      monitor = [ ",prefered,auto,${scale}" ];

      xwayland = {
        force_zero_scaling = true;
      };

      general = {
        gaps_in = 4;
        gaps_out = 4;
        border_size = 2;
        layout = "dwindle";
        # "col.active_border" = "rgba(7aa2f7aa)";
        # "col.inactive_border" = "rgba(414868aa)";
        allow_tearing = true;
      };

      input = {
        kb_layout = lib.mkDefault "us";
        # Remap caps to ctrl
        kb_options = "ctrl:nocaps";
        follow_mouse = true;
        touchpad = {
          natural_scroll = true;
        };
        accel_profile = "flat";
        sensitivity = 0;
        # Delay before a held-down key is repeated, in milliseconds. Default: 600
        repeat_delay = 300;
        force_no_accel = true;
      };

      # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
      dwindle = {
        pseudotile = true; # Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true; # You probably want this
      };

      # see https://wiki.hyprland.org/Configuring/Variables/#decoration
      decoration = {
        drop_shadow = false;
        blur = {
          enabled = false;
        };
      };

      # see https://wiki.hyprland.org/Configuring/Variables/#animations
      animations = {
        enabled = false;
        bezier = [
          "linear, 0, 0, 1, 1"
          "md3_standard, 0.2, 0, 0, 1"
          "md3_decel, 0.05, 0.7, 0.1, 1"
          "md3_accel, 0.3, 0, 0.8, 0.15"
          "overshot, 0.05, 0.9, 0.1, 1.1"
          "crazyshot, 0.1, 1.5, 0.76, 0.92"
          "hyprnostretch, 0.05, 0.9, 0.1, 1.0"
          "menu_decel, 0.1, 1, 0, 1"
          "menu_accel, 0.38, 0.04, 1, 0.07"
          "easeInOutCirc, 0.85, 0, 0.15, 1"
          "easeOutCirc, 0, 0.55, 0.45, 1"
          "easeOutExpo, 0.16, 1, 0.3, 1"
          "softAcDecel, 0.26, 0.26, 0.15, 1"
          "md2, 0.4, 0, 0.2, 1"
        ];
        animation = [
          "windows, 1, 3, md3_decel, popin 60%"
          "windowsIn, 1, 3, md3_decel, popin 60%"
          "windowsOut, 1, 3, md3_accel, popin 60%"
          "border, 1, 10, default"
          "fade, 1, 3, md3_decel"
          "layersIn, 1, 3, menu_decel, slide"
          "layersOut, 1, 1.6, menu_accel"
          "fadeLayersIn, 1, 2, menu_decel"
          "fadeLayersOut, 1, 4.5, menu_accel"
          "workspaces, 1, 7, menu_decel, slide"
          "specialWorkspace, 1, 3, md3_decel, slidevert"
        ];
      };

      # see https://wiki.hyprland.org/Configuring/Variables/#cursor
      cursor = {
        enable_hyprcursor = true;
      };

      # Allows for repeatable binds (press n hold)
      binde = [
        # Screen resize
        "$mod ALT, h, resizeactive, -20 0"
        "$mod ALT, l, resizeactive, 20 0"
        "$mod ALT, k, resizeactive, 0 -20"
        "$mod ALT, j, resizeactive, 0 20"

        # Audio keys
        ", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"

        # Playback keys
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPause, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # Brightness keys
        ", XF86MonBrightnessUp, exec, brightnessctl s 5%+"
        ", XF86MonBrightnessDown, exec, brightnessctl s 5%-"
      ];

      bind = [
        # General
        "$mod, return, exec, $terminal"
        "$mod, SPACE, exec, rofi -show drun"
        "$mod SHIFT, q, killactive"
        # "$mod SHIFT, e, exit"
        # "$mod SHIFT, p, pseudo"
        # "$mod SHIFT, l, exec, ${pkgs.hyprlock}/bin/hyprlock"

        # Screen focus
        "$mod, v, togglefloating"
        "$mod, u, focusurgentorlast"
        "$mod, tab, focuscurrentorlast"
        "$mod, f, fullscreen, 1"

        # Workspaces
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move to workspaces
        "$mod SHIFT, 1, movetoworkspace,1"
        "$mod SHIFT, 2, movetoworkspace,2"
        "$mod SHIFT, 3, movetoworkspace,3"
        "$mod SHIFT, 4, movetoworkspace,4"
        "$mod SHIFT, 5, movetoworkspace,5"
        "$mod SHIFT, 6, movetoworkspace,6"
        "$mod SHIFT, 7, movetoworkspace,7"
        "$mod SHIFT, 8, movetoworkspace,8"
        "$mod SHIFT, 9, movetoworkspace,9"
        "$mod SHIFT, 0, movetoworkspace,10"

        # Navigation
        "$mod, h, movefocus, l"
        "$mod, l, movefocus, r"
        "$mod, k, movefocus, u"
        "$mod, j, movefocus, d"

        # Swap windows
        "$mod SHIFT, h, swapwindow, l"
        "$mod SHIFT, l, swapwindow, r"
        "$mod SHIFT, k, swapwindow, u"
        "$mod SHIFT, j, swapwindow, d"

        # Applications
        # "$mod ALT, f, exec, ${pkgs.firefox}/bin/firefox"
        # "$mod ALT, v, exec, ${unstable.vesktop}/bin/vesktop"
        # "$mod ALT, e, exec, $terminal --hold -e ${pkgs.yazi}/bin/yazi"
        # "$mod ALT, o, exec, ${pkgs.obsidian}/bin/obsidian"
        # "$mod, r, exec, pkill fuzzel || ${pkgs.fuzzel}/bin/fuzzel"
        # "$mod ALT, r, exec, pkill anyrun || ${pkgs.anyrun}/bin/anyrun"
        "$mod ALT, n, exec, swaync-client -t -sw"

        # Clipboard
        "$mod ALT, v, exec, pkill fuzzel || cliphist list | fuzzel --no-fuzzy --dmenu | cliphist decode | wl-copy"

        # Screencapture
        # "$mod, S, exec, ${pkgs.grim}/bin/grim | wl-copy"
        # "$mod SHIFT+ALT, S, exec, ${pkgs.grim}/bin/grim -g \"$(slurp)\" - | ${pkgs.swappy}/bin/swappy -f -"
      ];

      windowrulev2 = [
        # prevent maximizing
        "suppressevent maximize, class:.*" # You'll probably like this.

        # bind apps to workspaces
        "workspace 1 silent, class:^(firefox)$"
        "workspace 1 silent, class:^(brave-browser)$"
        "workspace 2 silent, class:^(org.qbittorrent.qBittorrent)$"
        "workspace 3 silent, class:^(kitty)$"
        "workspace 3 silent, class:^(Alacritty)$"
        "workspace 4 silent, class:^(org.telegram.desktop)$"
        "workspace 4 silent, class:^(vesktop)$"
        "workspace 5 silent, initialTitle:^Spotify.*$"

        # firefox Picture-in-Picture
        "float,class:^(firefox)$,title:^(Picture-in-Picture)$"
        "pin,class:^(firefox)$,title:^(Picture-in-Picture)$"
        "float,class:^(firefox)$,title:^(Firefox — Sharing Indicator)$"
      ];

      windowrule = [
        # window rules to prevent screen from turning off
        "idleinhibit fullscreen,firefox"
        "idleinhibit fullscreen,brave"
        "idleinhibit fullscreen,mpv"
        "noborder,^(rofi)$"
      ];

      env = [
        # Hint electron apps to use wayland
        "NIXOS_OZONE_WL,1"
        "_JAVA_AWT_WM_NONREPARENTING,1"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "QT_QPA_PLATFORM,wayland"
        "SDL_VIDEODRIVER,wayland"
        "GDK_BACKEND,wayland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "HYPRCURSOR_SIZE,24"
        "XCURSOR_SIZE,24"
      ];

      exec-once = [
        "brave"
        "$terminal"
        "vesktop"
        "spotify"
        "telegram-desktop"
        "qbittorrent"
        "dunst"
        "nm-applet --indicator"
        "swww init & sleep 0.5 && exec wallpaper_random"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP &"
        "hash dbus-update-activation-environment 2>/dev/null"
        # "eval $(gnome-keyring-daemon --start --components=secrets,ssh,gpg,pkcs11)"
        # "export SSH_AUTH_SOCK"
        # "${pkgs.plasma5Packages.polkit-kde-agent}/libexec/polkit-kde-authentication-agent-1"
      ];
    };
  };
}
