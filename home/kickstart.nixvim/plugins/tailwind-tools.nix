{ pkgs, pkgs-unstable, ... }:
let
  unstable = pkgs-unstable;
in
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [ tailwind-tools-nvim ];
    extraConfigLua = ''
      require("tailwind-tools").setup({
        -- your configuration
      })  
    '';
  };
}
