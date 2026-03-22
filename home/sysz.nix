{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # systemd tui
    sysz
  ];
}
