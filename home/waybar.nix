{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.waybar = {
    enable = true;
    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: MesloLGS Nerd Font Mono;
        font-weight: 600;
        font-size: 12px;
        min-height: 0;
      }

      window#waybar {
        background: #12131a;
        color: white;
      }

      #workspaces {
        background-color: #1d202e;
        margin: 5px;
        margin-left: 6px;
        border-radius: 5px;
      }
      #workspaces button {
        padding: 2px 8px;
        color: #fff;
      }

      #workspaces button.active {
        color: #24283b;
        background-color: #7aa2f7;
        border-radius: 5px;
      }

      #workspaces button:hover {
        background-color: #7dcfff;
        color: #24283b;
        border-radius: 5px;
      }

      #custom-date,
      #clock,
      #battery,
      #pulseaudio,
      #network,
      #backlight {
        background-color: #1d202e;
        padding: 2px 10px;
        margin: 5px 0px;
      }

      #custom-date {
        color: #7dcfff;
      }

      #custom-power {
        color: #24283b;
        background-color: #db4b4b;
        border-radius: 5px;
        margin-right: 10px;
        margin-top: 5px;
        margin-bottom: 5px;
        margin-left: 0px;
        padding: 3px 10px;
      }

      #clock {
        color: #b48ead;
        border-radius: 0px 5px 5px 0px;
        margin-right: 6px;
      }

      #battery {
        color: #9ece6a;
      }

      #battery.charging {
        color: #9ece6a;
      }

      #battery.warning:not(.charging) {
        background-color: #f7768e;
        color: #24283b;
        border-radius: 5px 5px 5px 5px;
      }

      #network {
        color: #f7768e;
        border-radius: 5px 0px 0px 5px;
      }

      #pulseaudio, #backlight {
        color: #e0af68;
      }

      #temperature {
        background-color: #24283b;
        margin: 5px 0;
        padding: 0 10px;
        border-top-left-radius: 5px;
        border-bottom-left-radius: 5px;
        color: #82e4ff;
      }

      #disk {
        color: #b9f27c;
        margin: 5px 0;
        padding-right: 10px;
        background-color: #24283b;
        border-top-right-radius: 5px;
        border-bottom-right-radius: 5px;
        margin-right: 3px;
      }

      #memory {
        margin-left: 5px;
        background: #2a3152;
        margin: 5px 0;
        padding: 0 10px;
        margin-left: 3px;
        border-top-left-radius: 5px;
        border-bottom-left-radius: 5px;
        color: #ff9e64;
      }

      #cpu {
        margin: 5px 0;
        padding: 0 10px;
        background-color: #2a3152;
        color: #ff7a93;
        border-top-right-radius: 5px;
        border-bottom-right-radius: 5px;
        margin-right: 6px;
      }

      #tray {
        background-color: #455085;
        margin: 5px;
        margin-left: 0px;
        margin-right: 6px;
        border-radius: 5px;
        padding: 0 10px;
      }

      #tray > * {
        padding: 0 2px;
        margin: 0 2px;
      }
    '';
    settings = [
      {
        "layer" = "top";
        "position" = "top";
        modules-left = [ "hyprland/workspaces" ];
        modules-right = [
          "network"
          "pulseaudio"
          "backlight"
          "battery"
          "custom/date"
          "clock"
          "temperature"
          "disk"
          "memory"
          "cpu"
          "tray"
        ];
        "hyprland/workspaces" = {
          "disable-scroll" = true;
          "on-click" = "activate";
          # // "all-outputs": false,
          "format" = "{name}";
          "on-scroll-up" = "hyprctl dispatch workspace m-1 > /dev/null";
          "on-scroll-down" = "hyprctl dispatch workspace m+1 > /dev/null";
          "format-icons" = {
            "browser" = "";
            "media" = "";
            "code" = "";
            "chat" = "";
            "music" = "";
            "urgent" = "";
            "active" = "";
            "default" = "";
          };
        };
        "custom/date" = {
          "format" = "󰸗";
          "interval" = 3600;
          # "exec" = "/home/loki/bin/waybar-date.sh";
        };
        "custom/power" = {
          "format" = "󰐥";
          # "on-click" = "/home/loki/bin/waybar-power.sh";
        };
        "clock" = {
          format = " {:L%H:%M}";
          tooltip = true;
          tooltip-format = "<big>{:%A, %d.%B %Y }</big>\n<tt><small>{calendar}</small></tt>";
        };
        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󱘖 {capacity}%";
          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          on-click = "";
          tooltip = false;
        };
        "temperature" = {
          "hwmon-path" = "/sys/class/hwmon/hwmon4/temp1_input";
          "format" = "CPU {temperatureC}°C ";
        };
        "network" = {
          format-icons = [
            "󰤯"
            "󰤟"
            "󰤢"
            "󰤥"
            "󰤨"
          ];
          format-ethernet = " {bandwidthDownOctets} {essid}";
          format-wifi = "{icon} {signalStrength}% {essid}";
          format-disconnected = "󰤮";
          tooltip = true;
        };
        "pulseaudio" = {
          format = "{icon} {volume}% {format_source}";
          format-bluetooth = "{volume}% {icon} {format_source}";
          format-bluetooth-muted = " {icon} {format_source}";
          format-muted = " {format_source}";
          format-source = " {volume}%";
          format-source-muted = "";
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
        };
        "backlight" = {
          "format" = "{icon} {percent}%";
          "format-icons" = [
            ""
            ""
            ""
            ""
            ""
            ""
            ""
            ""
            ""
          ];
        };
        "tray" = {
          "icon-size" = 13;
          "spacing" = 5;
        };
        "disk" = {
          "interval" = 5;
          "format" = "  {free}";
          "path" = "/";
        };
        "memory" = {
          "interval" = 5;
          "format" = " {}%";
        };
        "cpu" = {
          "interval" = 10;
          "format" = " {usage:2}%";
          "max-length" = 20;
        };
      }
    ];
  };
}
