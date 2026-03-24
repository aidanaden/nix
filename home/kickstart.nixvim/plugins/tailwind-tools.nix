{pkgs, ...}: {
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [tailwind-tools-nvim];
    extraConfigLua = ''
      require("tailwind-tools").setup({
        -- your configuration
      })
    '';
  };
}
