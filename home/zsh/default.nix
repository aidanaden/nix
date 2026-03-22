{
  config,
  pkgs,
  pkgs-zsh-fzf-tab,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    autocd = true;
    dotDir = "${config.xdg.configHome}/zsh";
    autosuggestion.enable = true;

    history = {
      expireDuplicatesFirst = true;
      ignoreDups = true;
      ignoreSpace = true; # ignore commands starting with a space
      save = 20000;
      size = 20000;
      share = true;
    };

    shellAliases = {
      # builtins
      size = "du -sh";
      cp = "cp -i";
      mkdir = "mkdir -p";
      df = "df -h";
      free = "free -h";
      du = "du -sh";
      del = "rm -rf";
      lst = "ls --tree -I .git";
      lsl = "ls -l";
      lsa = "ls -a";
      null = "/dev/null";

      # overrides
      cat = "bat";
      top = "btop";
      htop = "btop";
      ping = "gping";
      diff = "delta";
      ssh = "TERM=screen ssh";
      python = "python3";
      pip = "python3 -m pip";
      venv = "python3 -m venv";
      pn = "pnpm";
      vim = "nvim";
      dig = "dog";
      # lazyjj shortcut
      lj = "lazyjj";
      # jj shortcuts
      j = "jj";
      jn = "jj new ";
      jp = "jj git push";
      jf = "jj git fetch";
      js = "jj st";
      # ps alternative
      ps = "procs";
      jrb = "j rebase -s \"all:children(main) & (bookmarks(glob:'aidan/*') | parents(bookmarks(glob:'aidan/*')))\" -d main";
    };

    # initExtraFirst = ''
    #   source ~/.p10k.zsh
    # '';

    initContent = ''
      # sops-nix age key from macOS Keychain
      export SOPS_AGE_KEY=$(security find-generic-password -a 'sops-age' -s 'sops-age-key' -w 2>/dev/null)

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      # tmux list sessions on startup
      function _tmux()
      {
          if [[ $# == 0 ]] && command tmux ls >& /dev/null; then
              command tmux attach \; choose-tree -s
          else
              command tmux "$@"
          fi
      }
      alias tmux=_tmux

      export VI_MODE_SET_CURSOR=true

      export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

      # zig build fix, see https://github.com/ziglang/zig/issues/19400
      export ZIG_GLOBAL_CACHE_DIR="$HOME/.cache/zig"

      # FZF lazy-loading - defer subprocess spawn until first use (~35ms savings)
      if [[ $options[zle] = on ]]; then
        __fzf_loaded=0
        __fzf_lazy_load() {
          (( __fzf_loaded )) && return
          __fzf_loaded=1
          source <(${pkgs.fzf}/bin/fzf --zsh)
        }
        __fzf_history_widget() { __fzf_lazy_load; fzf-history-widget }
        __fzf_file_widget() { __fzf_lazy_load; fzf-file-widget }
        __fzf_cd_widget() { __fzf_lazy_load; fzf-cd-widget }
        zle -N __fzf_history_widget
        zle -N __fzf_file_widget
        zle -N __fzf_cd_widget
        bindkey '^R' __fzf_history_widget
        bindkey '^T' __fzf_file_widget
        bindkey '\ec' __fzf_cd_widget

        export PATH=/Users/aidan/.opencode/bin:$PATH
      fi

      # Convert existing jj repo to colocated mode (enables gitsigns support)
      function jj-colocate() {
        if [[ ! -d .jj ]]; then
          echo "Error: Not in a jj repository"
          return 1
        fi
        if [[ -d .git ]]; then
          echo "Error: .git already exists - repo may already be colocated"
          return 1
        fi
        if [[ ! -d .jj/repo/store/git ]]; then
          echo "Error: No git backend found at .jj/repo/store/git"
          return 1
        fi

        echo "Converting to colocated repo..."
        echo '/*' > .jj/.gitignore
        mv .jj/repo/store/git .git
        printf '%s' '../../../.git' > .jj/repo/store/git_target
        git config --unset core.bare
        jj new && jj undo
        echo "Done! Repo is now colocated."
      }
    '';

    plugins = [
      {
        name = "fast-syntax-highlighting";
        src = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
      }
      {
        name = "zsh-nix-shell";
        src = "${pkgs.zsh-nix-shell}/share/zsh-nix-shell";
      }
      {
        name = "forgit";
        src = "${pkgs.zsh-forgit}/share/zsh/zsh-forgit";
      }
      {
        name = "fzf-tab";
        src = "${pkgs-zsh-fzf-tab.zsh-fzf-tab}/share/fzf-tab";
      }
      {
        name = "powerlevel10k";
        src = "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/";
        file = "powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = ./p10k-config;
        file = "p10k.zsh";
      }
    ];

    # oh-my-zsh = {
    #   enable = true;
    #   plugins = [];
    # };

    prezto = {
      enable = true;
      caseSensitive = false;
      utility.safeOps = true;
      editor = {
        dotExpansion = true;
        keymap = "vi";
      };
      prompt = {
        theme = "off";
      };
      pmodules = [
        "directory"
        "editor"
        "git"
        "terminal"
      ];
    };
  };
}
