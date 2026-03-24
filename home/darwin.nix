{config, ...}: {
  imports = [
    ./default.nix
    ./aerospace.nix
    ./stylix.nix
    ./chrome.nix
    ./pam_reattach.nix
    ./darwin-stats.nix
    ./amp.nix
  ];

  # Disable Linux-only stylix targets on Darwin
  stylix.targets.waybar.enable = false;

  launchd.agents.tmux-ghostty = {
    enable = true;
    config = {
      Label = "com.user.tmux-ghostty";
      ProgramArguments = [
        "/usr/bin/open"
        "-na"
        "Ghostty"
        "--args"
        "-e"
        "tmux"
      ];
      RunAtLoad = true;
    };
  };

  launchd.agents.finetune = {
    enable = true;
    config = {
      Label = "com.user.finetune";
      ProgramArguments = [
        "/usr/bin/open"
        "-a"
        "FineTune"
      ];
      RunAtLoad = true;
    };
  };

  launchd.agents.takopi = {
    enable = true;
    config = {
      Label = "com.user.takopi";
      ProgramArguments = ["${config.home.profileDirectory}/bin/takopi"];
      WorkingDirectory = "${config.home.homeDirectory}/projects/takopi-bot";
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = "/opt/homebrew/bin:${config.home.homeDirectory}/.opencode/bin:${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
    };
  };
}
