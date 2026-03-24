{
  programs.nixvim = {
    plugins.harpoon = {
      enable = true;
      lazyLoad = {
        enable = true;
        settings = {
          keys = [
            "<leader>h"
            "<leader>1"
            "<leader>2"
            "<leader>3"
            "<leader>4"
            "<leader>5"
            "<leader>6"
            "<C-a>"
          ];
        };
      };
    };

    keymaps = [
      {
        mode = "n";
        key = "<C-a>";
        action.__raw = "function() require'harpoon':list():add() end";
        options.desc = "Harpoon add file";
      }
      {
        mode = "n";
        key = "<leader>h";
        action.__raw = "function() require'harpoon'.ui:toggle_quick_menu(require'harpoon':list()) end";
        options.desc = "Harpoon toggle menu";
      }
      {
        mode = "n";
        key = "<leader>1";
        action.__raw = "function() require'harpoon':list():select(1) end";
        options.desc = "Harpoon file 1";
      }
      {
        mode = "n";
        key = "<leader>2";
        action.__raw = "function() require'harpoon':list():select(2) end";
        options.desc = "Harpoon file 2";
      }
      {
        mode = "n";
        key = "<leader>3";
        action.__raw = "function() require'harpoon':list():select(3) end";
        options.desc = "Harpoon file 3";
      }
      {
        mode = "n";
        key = "<leader>4";
        action.__raw = "function() require'harpoon':list():select(4) end";
        options.desc = "Harpoon file 4";
      }
      {
        mode = "n";
        key = "<leader>5";
        action.__raw = "function() require'harpoon':list():select(5) end";
        options.desc = "Harpoon file 5";
      }
      {
        mode = "n";
        key = "<leader>6";
        action.__raw = "function() require'harpoon':list():select(6) end";
        options.desc = "Harpoon file 6";
      }
    ];
  };
}
