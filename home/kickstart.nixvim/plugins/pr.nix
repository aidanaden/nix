{ pkgs, ... }:
let
  pr-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "pr.nvim";
    version = "unstable-2026-02-09";
    src = pkgs.fetchFromGitHub {
      owner = "0xKitsune";
      repo = "pr.nvim";
      rev = "a4ea1ad5f96f26a1a2853eb863eb4e9ed60f93c1";
      hash = "sha256-rwllIyY2RG58RmIpIDCUhn4VeIp9ED18MPtPOpi0OF0=";
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = [
      {
        plugin = pr-nvim;
        optional = true;
      }
    ];

    plugins.lz-n.plugins = [
      {
        __unkeyed-1 = "pr.nvim";
        cmd = [ "PR" ];
        after = ''
          function()
            require("pr").setup()
          end
        '';
      }
    ];

    keymaps = [
      {
        mode = "n";
        key = "<leader>pr";
        action = "<cmd>PR<CR>";
        options = {
          desc = "[P]ull [R]eview";
        };
      }
    ];
  };
}
