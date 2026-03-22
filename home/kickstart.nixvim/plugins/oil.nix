{
  programs.nixvim = {
    plugins.oil = {
      enable = true;
      settings = {
        view_options = {
          show_hidden = true;
        };
        use_default_keymaps = true;
        skip_confirm_for_simple_edits = true;
      };
    };
    keymaps = [
      {
        mode = "n";
        key = "-";
        action = ":Oil<CR>";
        options = {
          desc = "Open parent directory";
          silent = true;
        };
      }
    ];
  };
}
