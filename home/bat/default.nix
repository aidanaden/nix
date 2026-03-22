{ pkgs, ... }:
{
  programs.bat = {
    enable = true;
    # themes = {
    #   tokyo-night = {
    #     src = pkgs.fetchFromGitHub {
    #       owner = "folke";
    #       repo = "tokyonight.nvim";
    #       rev = "4b386e66a9599057587c30538d5e6192e3d1c181";
    #       sha256 = "sha256-kxsNappeZSlUkPbxlgGZKKJGGZj2Ny0i2a+6G+8nH7s=";
    #     };
    #     file = "extras/sublime/tokyonight_night.tmTheme";
    #   };
    # };
    # config = {
    #   theme = "tokyo-night";
    # };
  };
}
