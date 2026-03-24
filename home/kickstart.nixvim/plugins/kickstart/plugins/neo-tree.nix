{
  programs.nixvim = {
    plugins.neo-tree = {
      enable = true;
      lazyLoad = {
        enable = true;
        settings = {
          cmd = ["Neotree"];
          keys = ["\\"];
        };
      };

      settings.filesystem.window.mappings = {
        "\\" = "close_window";
      };
    };

    keymaps = [
      {
        key = "\\";
        action = "<cmd>Neotree reveal<cr>";
        options.desc = "NeoTree reveal";
      }
    ];
  };
}
