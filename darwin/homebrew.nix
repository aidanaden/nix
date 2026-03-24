_: {
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      # 'zap': uninstalls all formulae(and related files) not listed here.
      cleanup = "zap";
      upgrade = true;
    };

    taps = [
      "aidanaden/tools"
      "aidanaden/games"
      "productdevbook/tap"
    ];

    # `brew install`
    brews = [
      "displayplacer" # no nixpkgs package
      "aidanaden/tools/canvas-sync"
      "aidanaden/games/aztewoidz"
      "mole" # nixpkgs marks this broken on current pin
    ];

    # `brew install --cask`
    casks = [
      "codex" # always fetch latest version
      "lulu" # no nixpkgs package
      "arc" # no maintained nixpkgs package
      "raycast" # keep as /Applications app for dock path and system integration
      "finetune" # no nixpkgs package
      "ayugram" # ensure discoverable in Raycast via /Applications
      "balenaetcher" # no nixpkgs package
      "focusrite-control-2" # no nixpkgs package
      "crystalfetch" # no nixpkgs package
      "clop" # no nixpkgs package
      "cardinal-search" # no nixpkgs package
      "macfuse" # used for borg's mount feature to browse backups

      # apps re-added via Homebrew because unsupported/broken in current nixpkgs darwin pin
      "anki"
      "vesktop"
      "ledger-wallet"
      "ente-auth"
      "jellyfin-media-player"
      "mpv"
      "productdevbook/tap/portkiller"
      "obs"
      "vorta"
    ];
  };
}
