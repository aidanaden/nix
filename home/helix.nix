{
  pkgs,
  lib,
  ...
}: {
  # https://mynixos.com/home-manager/options/programs.helix
  programs.helix = {
    enable = true;
    package = pkgs.helix;
    settings = {
      # theme = "tokyonight";
      editor = {
        line-number = "relative";
        lsp = {
          display-inlay-hints = true;
          display-messages = true;
        };
      };
      keys.normal = {
        space.f = "file_picker";
        space.w = ":w";
        space.q = ":q";
        esc = [
          "collapse_selection"
          "keep_primary_selection"
        ];
      };
    };
    languages = {
      language = let
        prettier = lang: {
          command = lib.getExe pkgs.nodePackages.prettier;
          args = [
            "--stdin-filepath"
            "{}" # Helix replaces this with the file path, so Prettier can infer the parser
          ];
        };
      in [
        {
          name = "zig";
          auto-format = true;
        }
        {
          name = "bash";
          auto-format = true;
          formatter = {
            command = lib.getExe pkgs.shfmt;
            args = [
              "-i"
              "2"
            ];
          };
        }
        {
          name = "cmake";
          auto-format = true;
          language-servers = ["cmake-language-server"];
          formatter = {
            command = lib.getExe pkgs.cmake-format;
            args = ["-"];
          };
        }
        {
          name = "css";
          formatter = prettier "css";
          language-servers = [
            "tailwindcss-ls"
            "vscode-css-language-server"
          ];
        }
        {
          name = "javascript";
          auto-format = true;
          language-servers = [
            "typescript-language-server"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "typescript";
          auto-format = true;
          language-servers = [
            "typescript-language-server"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "tsx";
          auto-format = true;
          formatter = prettier "tsx";
          language-servers = [
            "typescript-language-server"
            "tailwindcss-ls"
            "vscode-eslint-language-server"
          ];
        }
        {
          name = "html";
          formatter = prettier "html";
          language-servers = [
            "vscode-html-language-server"
            "tailwindcss-ls"
          ];
        }
        {
          name = "markdown";
          language-servers = [
            "markdown-oxide"
          ];
        }
        {
          name = "nix";
          language-servers = [
            "nil"
          ];
        }
        {
          name = "python";
          auto-format = true;
          language-servers = [
            "basedpyright"
            "ruff"
          ];
        }
      ];

      language-server = {
        basedpyright.command = "${pkgs.basedpyright}/bin/basedpyright-langserver";

        zls = {
          command = lib.getExe pkgs.zls;
        };

        bash-language-server = {
          command = lib.getExe pkgs.bash-language-server;
          args = ["start"];
        };

        clangd = {
          command = "${pkgs.clang-tools}/bin/clangd";
          clangd.fallbackFlags = ["-std=c++2b"];
        };

        cmake-language-server = {
          command = lib.getExe pkgs.cmake-language-server;
        };

        dprint = {
          command = lib.getExe pkgs.dprint;
          args = ["lsp"];
        };

        nil = {
          command = lib.getExe pkgs.nil;
          config.nil.formatting.command = [
            "${lib.getExe pkgs.alejandra}"
            "-q"
          ];
        };

        ruff = {
          command = lib.getExe pkgs.ruff;
          args = ["server"];
        };

        tailwindcss-ls = {
          command = lib.getExe pkgs.tailwindcss-language-server;
          args = ["--stdio"];
          # Add this config block to solve monorepo issues
          config = {
            # This tells Helix to log all messages sent to/from the LSP
            trace.server = "verbose";
          };
        };

        typescript-language-server = {
          command = lib.getExe pkgs.nodePackages.typescript-language-server;
          args = ["--stdio"];
          config = {
            typescript-language-server.source = {
              addMissingImports.ts = true;
              fixAll.ts = true;
              organizeImports.ts = true;
              removeUnusedImports.ts = true;
              sortImports.ts = true;
            };
          };
        };

        vscode-css-language-server = {
          command = "${pkgs.nodePackages.vscode-langservers-extracted}/bin/vscode-css-language-server";
          args = ["--stdio"];
          config = {
            provideFormatter = true;
            css.validate.enable = true;
            scss.validate.enable = true;
          };
        };

        vscode-eslint-language-server = {
          command = "${pkgs.nodePackages.vscode-langservers-extracted}/bin/vscode-eslint-language-server";
          args = ["--stdio"];
        };
      };
    };
    # themes = {
    #   # taken from https://github.com/helix-editor/helix/blob/master/runtime/themes/tokyonight.toml
    #   tokyonight =
    #     let
    #       red = "#f7768e";
    #       orange = "#ff9e64";
    #       yellow = "#e0af68";
    #       light-green = "#9ece6a";
    #       green = "#73daca";
    #       aqua = "#2ac3de";
    #       teal = "#1abc9c";
    #       turquoise = "#89ddff";
    #       light-cyan = "#b4f9f8";
    #       cyan = "#7dcfff";
    #       blue = "#7aa2f7";
    #       purple = "#9d7cd8";
    #       magenta = "#bb9af7";
    #       comment = "#565f89";
    #       black = "#414868";
    #
    #       add = "#449dab";
    #       change = "#6183bb";
    #       delete = "#914c54";
    #
    #       error = "#db4b4b";
    #       info = "#0db9d7";
    #       hint = "#1abc9c";
    #
    #       fg = "#c0caf5";
    #       fg-dark = "#a9b1d6";
    #       fg-gutter = "#3b4261";
    #       fg-linenr = "#737aa2";
    #       fg-selected = "#343a55";
    #       border = "#15161e";
    #       border-highlight = "#27a1b9";
    #       bg = "#1a1b26";
    #       bg-inlay = "#1a2b32";
    #       bg-selection = "#283457";
    #       bg-menu = "#16161e";
    #       bg-focus = "#292e42";
    #     in
    #     {
    #       attribute = {
    #         fg = cyan;
    #       };
    #       "comment" = {
    #         fg = comment;
    #         modifiers = [ "italic" ];
    #       };
    #       "comment.block.documentation" = {
    #         fg = yellow;
    #       };
    #       constant = {
    #         fg = orange;
    #       };
    #       "constant.builtin" = {
    #         fg = aqua;
    #       };
    #       "constant.character" = {
    #         fg = light-green;
    #       };
    #       "constant.character.escape" = {
    #         fg = magenta;
    #       };
    #       constructor = {
    #         fg = aqua;
    #       };
    #       function = {
    #         fg = blue;
    #         modifiers = [ "italic" ];
    #       };
    #       "function.builtin" = {
    #         fg = aqua;
    #       };
    #       "function.macro" = {
    #         fg = cyan;
    #       };
    #       "function.special" = {
    #         fg = cyan;
    #       };
    #       keyword = {
    #         fg = purple;
    #         modifiers = [ "italic" ];
    #       };
    #       "keyword.control" = {
    #         fg = magenta;
    #       };
    #       "keyword.control.import" = {
    #         fg = cyan;
    #       };
    #       "keyword.control.return" = {
    #         fg = purple;
    #         modifiers = [ "italic" ];
    #       };
    #       "keyword.directive" = {
    #         fg = cyan;
    #       };
    #       "keyword.function" = {
    #         fg = magenta;
    #       };
    #       "keyword.operator" = {
    #         fg = magenta;
    #       };
    #       label = {
    #         fg = blue;
    #       };
    #       namespace = {
    #         fg = cyan;
    #       };
    #       operator = {
    #         fg = turquoise;
    #       };
    #       punctuation = {
    #         fg = turquoise;
    #       };
    #       special = {
    #         fg = aqua;
    #       };
    #       string = {
    #         fg = light-green;
    #       };
    #       "string.regexp" = {
    #         fg = light-cyan;
    #       };
    #       "string.special" = {
    #         fg = aqua;
    #       };
    #       tag = {
    #         fg = magenta;
    #       };
    #       type = {
    #         fg = aqua;
    #       };
    #       "type.builtin" = {
    #         fg = aqua;
    #       };
    #       "type.enum.variant" = {
    #         fg = orange;
    #       };
    #       variable = {
    #         fg = fg;
    #       };
    #       "variable.builtin" = {
    #         fg = red;
    #       };
    #       "variable.other.member" = {
    #         fg = green;
    #       };
    #       "variable.parameter" = {
    #         fg = yellow;
    #         modifiers = [ "italic" ];
    #       };
    #       "markup.bold" = {
    #         modifiers = [ "bold" ];
    #       };
    #       "markup.heading" = {
    #         fg = blue;
    #         modifiers = [ "bold" ];
    #       };
    #       "markup.heading.completion" = {
    #         bg = bg-menu;
    #         fg = fg;
    #       };
    #       "markup.heading.hover" = {
    #         bg = fg-selected;
    #       };
    #       "markup.italic" = {
    #         modifiers = [ "italic" ];
    #       };
    #       "markup.link" = {
    #         fg = blue;
    #         underline = {
    #           style = "line";
    #         };
    #       };
    #       "markup.link.label" = {
    #         fg = teal;
    #       };
    #       "markup.link.text" = {
    #         fg = teal;
    #       };
    #       "markup.link.url" = {
    #         underline = {
    #           style = "line";
    #         };
    #       };
    #       "markup.list" = {
    #         fg = orange;
    #         modifiers = [ "bold" ];
    #       };
    #       "markup.normal.completion" = {
    #         fg = comment;
    #       };
    #       "markup.normal.hover" = {
    #         fg = fg-dark;
    #       };
    #       "markup.raw" = {
    #         fg = teal;
    #       };
    #       "markup.raw.inline" = {
    #         bg = black;
    #         fg = blue;
    #       };
    #       "markup.strikethrough" = {
    #         modifiers = [ "crossed_out" ];
    #       };
    #       "diff.delta" = {
    #         fg = change;
    #       };
    #       "diff.delta.moved" = {
    #         fg = blue;
    #       };
    #       "diff.minus" = {
    #         fg = delete;
    #       };
    #       "diff.plus" = {
    #         fg = add;
    #       };
    #       error = {
    #         fg = error;
    #       };
    #       warning = {
    #         fg = yellow;
    #       };
    #       info = {
    #         fg = info;
    #       };
    #       hint = {
    #         fg = hint;
    #       };
    #       "diagnostic.error" = {
    #         underline = {
    #           style = "curl";
    #           color = error;
    #         };
    #       };
    #       "diagnostic.warning" = {
    #         underline = {
    #           style = "curl";
    #           color = yellow;
    #         };
    #       };
    #       "diagnostic.info" = {
    #         underline = {
    #           style = "curl";
    #           color = info;
    #         };
    #       };
    #       "diagnostic.hint" = {
    #         underline = {
    #           style = "curl";
    #           color = hint;
    #         };
    #       };
    #       "diagnostic.unnecessary" = {
    #         modifiers = [ "dim" ];
    #       };
    #       "diagnostic.deprecated" = {
    #         modifiers = [ "crossed_out" ];
    #       };
    #       "ui.background" = {
    #         bg = bg;
    #         fg = fg;
    #       };
    #       "ui.cursor" = {
    #         modifiers = [ "reversed" ];
    #       };
    #       "ui.cursor.match" = {
    #         fg = orange;
    #         modifiers = [ "bold" ];
    #       };
    #       "ui.cursorline.primary" = {
    #         bg = bg-menu;
    #       };
    #       "ui.help" = {
    #         bg = bg-menu;
    #         fg = fg;
    #       };
    #       "ui.linenr" = {
    #         fg = fg-gutter;
    #       };
    #       "ui.linenr.selected" = {
    #         fg = fg-linenr;
    #       };
    #       "ui.menu" = {
    #         bg = bg-menu;
    #         fg = fg;
    #       };
    #       "ui.menu.selected" = {
    #         bg = fg-selected;
    #       };
    #       "ui.popup" = {
    #         bg = bg-menu;
    #         fg = border-highlight;
    #       };
    #       "ui.selection" = {
    #         bg = bg-selection;
    #       };
    #       "ui.selection.primary" = {
    #         bg = bg-selection;
    #       };
    #       "ui.statusline" = {
    #         bg = bg-menu;
    #         fg = fg-dark;
    #       };
    #       "ui.statusline.inactive" = {
    #         bg = bg-menu;
    #         fg = fg-gutter;
    #       };
    #       "ui.statusline.normal" = {
    #         bg = blue;
    #         fg = bg;
    #         modifiers = [ "bold" ];
    #       };
    #       "ui.statusline.insert" = {
    #         bg = light-green;
    #         fg = bg;
    #         modifiers = [ "bold" ];
    #       };
    #       "ui.statusline.select" = {
    #         bg = magenta;
    #         fg = bg;
    #         modifiers = [ "bold" ];
    #       };
    #       "ui.text" = {
    #         fg = fg;
    #       };
    #       "ui.text.focus" = {
    #         bg = bg-focus;
    #       };
    #       "ui.text.inactive" = {
    #         fg = comment;
    #         modifiers = [ "italic" ];
    #       };
    #       "ui.text.info" = {
    #         bg = bg-menu;
    #         fg = fg;
    #       };
    #       "ui.text.directory" = {
    #         fg = cyan;
    #       };
    #       "ui.virtual.ruler" = {
    #         bg = fg-gutter;
    #       };
    #       "ui.virtual.whitespace" = {
    #         fg = fg-gutter;
    #       };
    #       "ui.virtual.inlay-hint" = {
    #         bg = bg-inlay;
    #         fg = teal;
    #       };
    #       "ui.virtual.jump-label" = {
    #         fg = orange;
    #         modifiers = [ "bold" ];
    #       };
    #       "ui.window" = {
    #         fg = border;
    #         modifiers = [ "bold" ];
    #       };
    #     };
    # };
  };
}
