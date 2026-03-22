{ pkgs, ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      selection_foreground = "none";

      tab_bar_style = "fade";
      tab_fade = "1";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "bold";

      tab_bar_background = "#101014";
      macos_titlebar_color = "#16161e";

      allow_hyperlinks = true;
      disable_ligatures = "never";
      macos_option_as_alt = true;
    };
  };
}
