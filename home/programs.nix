{
  pkgs,
  pkgs-unstable,
  terminal,
  inputs ? {},
  ...
}: let
  unstable = pkgs-unstable;
  inherit (pkgs.stdenv) isLinux;
  inherit (pkgs.stdenv) isDarwin;
  isPackageAvailable = pkg: (builtins.tryEval pkg.outPath).success;
  darwinPackages = pkgs.lib.filter isPackageAvailable (with pkgs; [
    # Keep Darwin-only package set resilient to unsupported/broken nixpkgs attrs.
    lc3tools
    rustmission
    borgbackup
    claude-code
    aerospace
    bitwarden-desktop
    orbstack
  ]);
  takopi = pkgs.writeShellApplication {
    name = "takopi";
    runtimeInputs = [
      pkgs.python314
      pkgs.uv
    ];
    text = ''
      exec uv tool run --python ${pkgs.python314}/bin/python3 --from takopi@latest takopi "$@"
    '';
  };
in {
  home = {
    packages = with pkgs;
      [
        # neovim

        git
        act # github action runner

        # node
        bun
        nodejs_22
        nodePackages.pnpm
        nodePackages.typescript
        nodePackages.typescript-language-server

        # node webpack analysing
        # nodePackages.webpack
        # nodePackages.webpack-cli

        # rush
        # nodePackages.rush

        # rust
        rustup

        # go
        unstable.goreleaser

        # make
        gnumake

        # libusb
        libusb1
        pkg-config

        # python
        python314
        pyenv
        uv
        ruff

        # clickhouse
        clickhouse

        # command line tools
        stow
        fd
        ripgrep
        tldr
        fastfetch

        # encryption & secrets
        age
        sops

        # cloud specific
        flyctl
        turso-cli
        google-cloud-sdk

        # video
        yt-dlp

        # video player and scripts (Linux only - wayland dependency)
      ]
      ++ pkgs.lib.optionals isLinux [
        mpv-unwrapped

        # japanese-learning
        mpvScripts.mpvacious

        # torrents (Linux only - Qt/wayland dependency)
        qbittorrent

        # discord client (Linux only - wayland dependency)
        unstable.vesktop

        # telegram (Linux only - wayland dependency)
        telegram-desktop
        ayugram-desktop
      ]
      ++ [
        # wireguard ui
        unstable.wireguard-ui

        # dog replacement
        dogdns

        # lshw alternative
        inxi

        # disk usage analyser
        unstable.ncdu

        # jujutsu tui
        unstable.lazyjj
        unstable.jjui

        # docker cli
        unstable.lazydocker

        # ai coding agent memory
        unstable.beads

        # telegram coding-agent bridge
        takopi

        # ps alternative
        unstable.procs

        # diff alternative
        difftastic

        # generate books from markdown (gameboy pandocs)
        mdbook

        # note-taking
        obsidian

        # solana dev tools (solana-cli, anchor)
        # unstable.solana-cli
        # unstable.anchor

        # zig
        unstable.zig

        # local https certs
        mkcert

        # c build tools
        ninja
        cmake
        automake
        autoconf

        # reverse engineering
        ghidra

        # utm virtualisation
        utm

        # radicle
        radicle-node
        radicle-explorer

        # httpie, curl alternative
        xh

        # swf flash game decompiler
        jpexs

        # rust command completion timer
        hyperfine

        # screenshot tool (Linux only - wayland dependency)
      ]
      ++ pkgs.lib.optionals isLinux [
        flameshot

        # performance profiling (Linux only - wayland dependency)
        tracy
      ]
      ++ [
        # cloudflare localhost tunneling
        cloudflared

        # sdl cross-platform graphics
        # SDL2
        # sdl3

        # crypto wallets

        # shamir cli
        # inputs.shamir.packages.${pkgs.system}.default

        # schnorr cli
        # inputs.schnorr.packages.${pkgs.system}.default

        # flow terminal
        # inputs.flow.packages.${pkgs.system}.default
      ]
      ++ pkgs.lib.optionals (inputs ? msgvault) [
        inputs.msgvault.packages.${pkgs.system}.default
      ]
      ++ [
        # rustmission
        # inputs.rustmission.packages.${pkgs.system}.default

        # signal terminal client
        gurk-rs
      ]
      ++ pkgs.lib.optionals isDarwin darwinPackages;
    sessionVariables = {
      EDITOR = "nvim";
      TERMINAL = "${terminal}";
    };
  };

  programs = {
    # let home-manager manage itself
    home-manager.enable = true;

    go = {
      enable = true;
      env = {
        GOPATH = "$HOME/go";
        GOBIN = "$HOME/go/bin";
        GOPRIVATE = "";
      };
    };

    # shell integrations are enabled by default
    zoxide.enable = true;
    jq.enable = true; # json parser
    nushell.enable = false; # zsh alternative
    broot.enable = false; # browser big folders
    eza.enable = true;

    fzf = {
      enable = true;
      enableZshIntegration = false; # lazy-loaded in zsh config
      defaultCommand = "fd --type f --hidden --follow --exclude .git --exclude .vim --exclude .cache --exclude vendor --exclude node_modules";
      defaultOptions = [
        "--border sharp"
        "--inline-info"
        "--color fg:#c0caf5,bg:#1a1b26,hl:#bb9af7,fg+:#c0caf5,bg+:#1a1b26,hl+:#7dcfff,info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff,marker:#9ece6a,spinner:#9ece6a,header:#9ece6a"
      ];
    };
  };
}
