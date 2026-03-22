{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # enable macos sudo touch id
    pam-reattach
  ];
}
