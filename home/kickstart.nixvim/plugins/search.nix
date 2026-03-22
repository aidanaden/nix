{
  pkgs,
  inputs ? { },
  ...
}:
let
  fff-plugin =
    if builtins.hasAttr "fff-nvim" inputs then
      inputs.fff-nvim.packages.${pkgs.system}.fff-nvim
    else
      pkgs.vimPlugins.fff-nvim;
in
{
  programs.nixvim = {
    plugins.telescope.enable = true;

    extraPlugins = [ fff-plugin ];

    extraConfigLua =
      ''
        require('fff').setup({
          preview = {
            line_numbers = true,
          },
        })
      ''
      + "\n"
      + builtins.readFile ./search.lua;

    keymaps = [
      {
        mode = "n";
        key = "<leader>sh";
        action.__raw = "function() require('aidan.search').search_help() end";
        options = {
          desc = "[S]earch [H]elp";
        };
      }
      {
        mode = "n";
        key = "<leader>sk";
        action.__raw = "function() require('aidan.search').search_keymaps() end";
        options = {
          desc = "[S]earch [K]eymaps";
        };
      }
      {
        mode = "n";
        key = "<leader>sf";
        action.__raw = "function() require('aidan.search').find_files() end";
        options = {
          desc = "[S]earch [F]iles";
        };
      }
      {
        mode = "n";
        key = "<leader>ss";
        action.__raw = "function() require('aidan.search').search_menu() end";
        options = {
          desc = "[S]earch [S]elect";
        };
      }
      {
        mode = "n";
        key = "<leader>sw";
        action.__raw = "function() require('aidan.search').search_word() end";
        options = {
          desc = "[S]earch current [W]ord";
        };
      }
      {
        mode = "n";
        key = "<leader>sg";
        action.__raw = "function() require('aidan.search').live_grep() end";
        options = {
          desc = "[S]earch by [G]rep";
        };
      }
      {
        mode = "n";
        key = "<leader>sd";
        action.__raw = "function() require('aidan.search').search_diagnostics() end";
        options = {
          desc = "[S]earch [D]iagnostics";
        };
      }
      {
        mode = "n";
        key = "<leader>sr";
        action.__raw = "function() require('aidan.search').resume() end";
        options = {
          desc = "[S]earch [R]esume";
        };
      }
      {
        mode = "n";
        key = "<leader>s";
        action.__raw = "function() require('aidan.search').search_recent_files() end";
        options = {
          desc = "[S]earch Recent Files";
        };
      }
      {
        mode = "n";
        key = "<leader><leader>";
        action.__raw = "function() require('aidan.search').search_buffers() end";
        options = {
          desc = "[ ] Find existing buffers";
        };
      }
      {
        mode = "n";
        key = "<leader>/";
        action.__raw = "function() require('aidan.search').search_current_buffer() end";
        options = {
          desc = "[/] Search in current buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>s/";
        action.__raw = "function() require('aidan.search').search_open_files() end";
        options = {
          desc = "[S]earch [/] in Open Files";
        };
      }
      {
        mode = "n";
        key = "<leader>sn";
        action.__raw = "function() require('aidan.search').find_config_files() end";
        options = {
          desc = "[S]earch [N]eovim files";
        };
      }
    ];
  };
}
