{
  lib,
  pkgs,
  user,
  hostname,
  ...
}: {
  imports = [./homebrew.nix];

  users.users.${user} = {
    home = "/Users/${user}";
    shell = pkgs.zsh;
  };

  networking = {
    computerName = hostname;
    hostName = hostname;
    localHostName = hostname;
  };

  environment = {
    variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      TERMINAL = "kitty";
    };
    etc."pam.d/sudo_local".text = ''
      # Managed by Nix Darwin
      auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
      auth       sufficient     pam_tid.so
    '';
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    scheherazade-new
    ia-writer-duospace
    meslo-lgs-nf
    monaspace
    departure-mono
    noto-fonts
    kanji-stroke-order-font
  ];

  services = {
    # Auto upgrade nix package and the daemon service.
    tailscale.enable = true;
  };

  nix = {
    optimise = {
      automatic = true;
    };

    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 3;
        Minute = 0;
      };
      options = "--delete-older-than 14d";
    };

    settings = {
      allowed-users = [user];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
      # produces linking issues when updating on macOS
      # https://github.com/NixOS/nix/issues/7273
      auto-optimise-store = false;

      substituters = [
        "https://nix-community.cachix.org"
        "https://nixvim.cachix.org"
        "https://numtide.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixvim.cachix.org-1:8OKL6bjWa7zwLLjGRWxP3jgCWr9J/Q1P2Aj1mNXZJ+M="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      ];
      builders-use-substitutes = true;
    };
  };

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  # this is required if you want to use darwin's default shell - zsh
  programs.zsh.enable = true;

  system = {
    primaryUser = user;
    # activationScripts are executed every time you boot the system or run `nixos-rebuild` / `darwin-rebuild`.
    activationScripts.postActivation.text = lib.mkAfter ''
      # Keep a stable app name that matches common "AyuGram Desktop" searches in launchers.
      if [ -d /Applications/AyuGram.app ]; then
        ln -sfn /Applications/AyuGram.app "/Applications/AyuGram Desktop.app"
      fi

      # Reserve Command+Space and Option+Command+Space for Raycast by disabling Spotlight shortcuts.
      SYMBOLIC_HOTKEYS="/Users/${user}/Library/Preferences/com.apple.symbolichotkeys.plist"
      if [ -f "$SYMBOLIC_HOTKEYS" ]; then
        /usr/bin/sudo -u ${user} /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled 0" "$SYMBOLIC_HOTKEYS" || true
        /usr/bin/sudo -u ${user} /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:65:enabled 0" "$SYMBOLIC_HOTKEYS" || true
      fi

      # Use mpv as the default media player for common audio/video types.
      if [ -d "/Applications/mpv.app" ]; then
        set_mpv_default() {
          /usr/bin/sudo -u ${user} ${pkgs.duti}/bin/duti -s io.mpv "$1" all || true
        }

        for media_type in public.audiovisual-content public.video public.movie public.audio; do
          set_mpv_default "$media_type"
        done

        for media_ext in mp4 m4v mov mkv webm avi mpg mpeg ts m2ts flv wmv 3gp ogv vob mp3 m4a aac flac wav aiff alac ogg opus oga wma mka m3u m3u8 pls xspf; do
          set_mpv_default "$media_ext"
        done

        for media_mime in video/mp4 video/webm video/quicktime video/x-matroska video/x-msvideo video/mpeg video/x-flv video/x-ms-wmv audio/mpeg audio/mp4 audio/aac audio/flac audio/wav audio/x-wav audio/ogg audio/opus application/ogg application/vnd.apple.mpegurl application/x-mpegurl; do
          set_mpv_default "$media_mime"
        done
      fi
    '';
    # activationScripts.postUserActivation.text = ''
    #   # activateSettings -u will reload the settings from the database and apply them to the current session,
    #   # so we do not need to logout and login again to make the changes take effect.
    #   /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
    # '';

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToControl = true;
    };

    defaults = {
      dock = {
        autohide = true;
        mru-spaces = false;
        orientation = "bottom";
        showhidden = true;
        static-only = true;
        persistent-apps = [
          "/Users/${user}/Applications/Home Manager Apps/Telegram.app"
          "/Applications/Vesktop.app"
          "/Users/${user}/Applications/Home Manager Apps/Spotify.app"
          "/Users/${user}/Applications/Home Manager Apps/kitty.app"
          "/Users/${user}/Applications/Home Manager Apps/qbittorrent.app"
          "/Applications/Raycast.app"
          "/Applications/Arc.app"
          "/Applications/Bitwarden.app"
        ];
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true; # enable two finger right click
        TrackpadThreeFingerDrag = true; # enable three finger drag
      };

      finder = {
        _FXShowPosixPathInTitle = true;
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      menuExtraClock = {
        ShowAMPM = false;
        ShowDate = 1; # Always
        Show24Hour = true;
        ShowSeconds = false;
      };

      # other macOS's defaults configuration.
      # ......
      CustomUserPreferences = {
        NSGlobalDomain = {
          # Add a context menu item for showing the Web Inspector in web views
          WebKitDeveloperExtras = true;
          InitialKeyRepeat = 10;
          KeyRepeat = 2;
          NSAutomaticCapitalizationEnabled = false;
          NSAutomaticDashSubstitutionEnabled = false;
          NSAutomaticPeriodSubstitutionEnabled = false;
          NSAutomaticQuoteSubstitutionEnabled = false;
          NSAutomaticSpellingCorrectionEnabled = false;
          "_HIHideMenuBar" = false;
        };
        "com.apple.AdLib" = {
          allowApplePersonalizedAdvertising = false;
        };
        "com.apple.controlcenter" = {
          BatteryShowPercentage = true;
        };
        "com.apple.spaces" = {
          "spans-displays" = 0; # Display have seperate spaces
        };
        "com.apple.finder" = {
          ShowExternalHardDrivesOnDesktop = true;
          ShowHardDrivesOnDesktop = true;
          ShowMountedServersOnDesktop = true;
          ShowRemovableMediaOnDesktop = true;
          _FXSortFoldersFirst = true;
          # When performing a search, search the current folder by default
          FXDefaultSearchScope = "SCcf";
        };
        "com.apple.desktopservices" = {
          # Avoid creating .DS_Store files on network or USB volumes
          DSDontWriteNetworkStores = true;
          DSDontWriteUSBStores = true;
        };
        "com.apple.screensaver" = {
          # Require password immediately after sleep or screen saver begins
          askForPassword = 0;
          askForPasswordDelay = 0;
        };
        "com.apple.screencapture" = {
          location = "~/Downloads";
          type = "png";
        };
        "com.apple.print.PrintingPrefs" = {
          # Automatically quit printer app once the print jobs complete
          "Quit When Finished" = true;
        };
        "com.apple.SoftwareUpdate" = {
          AutomaticCheckEnabled = true;
          # Check for software updates daily, not just once per week
          ScheduleFrequency = 1;
          # Download newly available updates in background
          AutomaticDownload = 0;
          # Install System data files & security updates
          CriticalUpdateInstall = 1;
        };
        "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
        # Prevent Photos from opening automatically when devices are plugged in
        "com.apple.ImageCapture".disableHotPlug = true;
        # Turn on app auto-update
        "com.apple.commerce".AutoUpdate = true;

        "com.raycast.macos" = {
          # Command+Space
          globalHotkey = {
            keyCode = 49;
            modifierFlags = 1048576;
          };
          raycastGlobalHotkey = {
            keyCode = 49;
            modifierFlags = 1048576;
          };
          raycastHotkey = {
            keyCode = 49;
            modifierFlags = 1048576;
          };
          useSpotlightAsRaycastHotkey = false;
          "mainWindow_isMonitoringGlobalHotkeys" = true;
        };

        # "com.apple.Safari" = {
        #   # Privacy: don’t send search queries to Apple
        #   UniversalSearchEnabled = false;
        #   SuppressSearchSuggestions = true;
        #   # Press Tab to highlight each item on a web page
        #   WebKitTabToLinksPreferenceKey = true;
        #   ShowFullURLInSmartSearchField = true;
        #   # Prevent Safari from opening ‘safe’ files automatically after downloading
        #   AutoOpenSafeDownloads = false;
        #   ShowFavoritesBar = false;
        #   IncludeInternalDebugMenu = true;
        #   IncludeDevelopMenu = true;
        #   WebKitDeveloperExtrasEnabledPreferenceKey = true;
        #   WebContinuousSpellCheckingEnabled = true;
        #   WebAutomaticSpellingCorrectionEnabled = false;
        #   AutoFillFromAddressBook = false;
        #   AutoFillCreditCardData = false;
        #   AutoFillMiscellaneousForms = false;
        #   WarnAboutFraudulentWebsites = true;
        #   WebKitJavaEnabled = false;
        #   WebKitJavaScriptCanOpenWindowsAutomatically = false;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks" = true;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = false;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled" = false;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles" = false;
        #   "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" = false;
        # };

        # "com.apple.mail" = {
        #   # Disable inline attachments (just show the icons)
        #   DisableInlineAttachmentViewing = true;
        # };
      };
    };
  };
}
