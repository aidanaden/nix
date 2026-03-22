{ pkgs, pkgs-unstable, lib, ... }:
{
  programs.nixvim = {
    extraConfigLuaPost = ''
      -- Generic escape hatch: temporarily disable format-on-save (globally or per-buffer).
      -- Useful when a formatter has a buggy transform (e.g. Tailwind class rewrites).
      vim.g.disable_autoformat = vim.g.disable_autoformat or true

      vim.api.nvim_create_user_command('FormatOnSaveDisable', function()
        vim.g.disable_autoformat = true
        vim.notify('format-on-save: OFF', vim.log.levels.INFO)
      end, {})

      vim.api.nvim_create_user_command('FormatOnSaveEnable', function()
        vim.g.disable_autoformat = false
        vim.notify('format-on-save: ON', vim.log.levels.INFO)
      end, {})

      vim.api.nvim_create_user_command('FormatOnSaveToggle', function()
        vim.g.disable_autoformat = not vim.g.disable_autoformat
        vim.notify('format-on-save: ' .. (vim.g.disable_autoformat and 'OFF' or 'ON'), vim.log.levels.INFO)
      end, {})

      vim.api.nvim_create_user_command('FormatOnSaveBufferToggle', function()
        vim.b.disable_autoformat = not vim.b.disable_autoformat
        vim.notify('format-on-save (buffer): ' .. (vim.b.disable_autoformat and 'OFF' or 'ON'), vim.log.levels.INFO)
      end, {})
    '';

    # Autoformat
    # https://nix-community.github.io/nixvim/plugins/conform-nvim.html
    plugins.conform-nvim = {
      enable = true;
      settings = {
        notify_on_error = false;
        format_on_save = ''
          function(bufnr)
            if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
              return
            end

            -- Disable "format_on_save lsp_fallback" for lanuages that don't
            -- have a well standardized coding style. You can add additional
            -- lanuages here or re-enable it for the disabled ones.
            local disable_filetypes = { c = true, cpp = true }
            return {
              timeout_ms = 1500,
              lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype]
            }
          end
        '';
        formatters_by_ft = {
          lua = [ "stylua" ];
          # Conform can also run multiple formatters sequentially
          # python = [ "isort "black" ];
          #
          # You can use a sublist to tell conform to run *until* a formatter
          # is found
          # javascript = [ [ "prettierd" "prettier" ] ];
          # markdown = [ "prettierd" ];
          # mdx = [ "prettierd" ];
          rust = [ "rustfmt" ];
          typescript = {
            __unkeyed-1 = "oxfmt";
            __unkeyed-3 = "oxlint";
            stop_after_first = true;
          };
          typescriptreact = {
            __unkeyed-1 = "oxfmt";
            __unkeyed-3 = "oxlint";
            stop_after_first = true;
          };
          javascript = {
            __unkeyed-1 = "oxfmt";
            __unkeyed-2 = "oxlint";
            stop_after_first = true;
          };
          javascriptreact = {
            __unkeyed-1 = "oxfmt";
            __unkeyed-2 = "oxlint";
            stop_after_first = true;
          };
          # astro = {
          #   __unkeyed-1 = "prettierd";
          #   __unkeyed-2 = "eslint_d";
          #   __unkeyed-3 = "eslint";
          #   __unkeyed-4 = "prettier";
          #   stop_after_first = true;
          # };
          # yaml = [ "yamlfmt" ];
          # toml = [ "taplo" ];
          # sql = [ "sqlfluff" ];
          nix = [ "nixfmt-rfc-style" ];
          zig = [ "zigfmt" ];
          # "_" = [
          #   "squeeze_blanks"
          #   "trim_whitespace"
          #   "trim_newlines"
          # ];
        };

        formatters = {
          nixfmt-rfc-style = {
            command = lib.getExe pkgs.nixfmt-rfc-style;
          };
          # prettierd = {
          #   command = lib.getExe pkgs.prettierd;
          # };
          # eslint_d = {
          #   command = lib.getExe pkgs.eslint_d;
          # };
          rustfmt = {
            command = lib.getExe pkgs.rustfmt;
          };
          oxlint = {
            command = lib.getExe pkgs.oxlint;
          };
          oxfmt = {
            command = lib.getExe pkgs-unstable.oxfmt;
            args = [ "--stdin-filepath" "$FILENAME" ];
          };
          # sqlfluff = {
          #   command = lib.getExe pkgs.sqlfluff;
          # };
          # squeeze_blanks = {
          #   command = lib.getExe' pkgs.coreutils "cat";
          # };
          stylua = {
            command = lib.getExe pkgs.stylua;
          };
          # taplo = {
          #   command = lib.getExe pkgs.taplo;
          # };
          # yamlfmt = {
          #   command = lib.getExe pkgs.yamlfmt;
          # };
          zigfmt = {
            command = lib.getExe pkgs.zig;
          };
        };
      };
    };

    # https://nix-community.github.io/nixvim/keymaps/index.html
    keymaps = [
      {
        mode = "";
        key = "<leader>f";
        action.__raw = ''
          function()
            require('conform').format { async = true, lsp_fallback = true }
          end
        '';
        options = {
          desc = "[F]ormat buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>uf";
        action = "<cmd>FormatOnSaveBufferToggle<cr>";
        options = {
          desc = "Toggle format-on-save (buffer)";
        };
      }
    ];
  };
}
