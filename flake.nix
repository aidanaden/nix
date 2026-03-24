{
  description = "NixOS and nix-darwin configurations for personal infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    stylix = {
      url = "github:danth/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    mac-app-util.url = "github:hraban/mac-app-util";
    zig.url = "github:mitchellh/zig-overlay";
    msgvault.url = "github:wesm/msgvault";

    fff-nvim = {
      url = "github:dmtrKovalenko/fff.nvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    nixpkgs-zsh-fzf-tab = {
      url = "github:nixos/nixpkgs/8193e46376fdc6a13e8075ad263b4b5ca2592c03";
    };

    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-darwin,
    nixpkgs-unstable,
    treefmt-nix,
    disko,
    sops-nix,
    darwin,
    home-manager,
    nix-index-database,
    nixvim,
    stylix,
    mac-app-util,
    zig,
    nixpkgs-zsh-fzf-tab,
    colmena,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    linuxSystem = "x86_64-linux";
    darwinSystem = "aarch64-darwin";
    darwinUser = "aidan";
    darwinHost = "m4";
    darwinTerminal = "kitty";

    linuxPkgsFor = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

    unstablePkgsFor = system:
      import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

    darwinNixpkgsConfig = {
      allowUnfree = true;
      allowUnsupportedSystem = false;
    };

    darwinOverlays = [
      zig.overlays.default
      (
        _final: prev: {
          nodejs = prev.nodejs_22;
          nodejs-slim = prev.nodejs-slim_22;
        }
      )
    ];

    linuxSpecialArgs = system: {
      inherit inputs;
      pkgs-unstable = unstablePkgsFor system;
    };

    linuxModules = hostPath: [
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
      hostPath
    ];

    mkLinuxHost = hostPath:
      nixpkgs.lib.nixosSystem {
        system = linuxSystem;
        specialArgs = linuxSpecialArgs linuxSystem;
        modules = linuxModules hostPath;
      };

    treefmtEvalFor = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.alejandra.enable = true;
        programs.deadnix.enable = true;
        programs.statix.enable = true;
        programs.shfmt.enable = true;
        programs.prettier.enable = true;

        settings.global.excludes = [
          ".beads/**"
          "AGENTS.md"
          "compose/authelia/secrets/.gitkeep"
          "result/**"
          "result-*/**"
          "secrets/secrets.yaml"
        ];

        settings.formatter.prettier.excludes = [
          "secrets/secrets.yaml"
        ];

        settings.formatter.alejandra.includes = ["**/*.nix"];
        settings.formatter.deadnix.includes = ["**/*.nix"];
        settings.formatter.statix.includes = ["**/*.nix"];
      };

    treefmtEval = forAllSystems treefmtEvalFor;

    rotateAmcrestRtspPasswordFor = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonTool =
        pkgs.writers.writePython3Bin
        "rotate-amcrest-rtsp-password"
        {}
        (builtins.readFile ./scripts/rotate-amcrest-rtsp-password.py);
    in
      pkgs.symlinkJoin {
        name = "rotate-amcrest-rtsp-password";
        paths = [pythonTool];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram "$out/bin/rotate-amcrest-rtsp-password" \
            --prefix PATH : ${
            nixpkgs.lib.makeBinPath [
              pkgs.jujutsu
              pkgs.nix
              pkgs.openssh
              pkgs.sops
            ]
          }
        '';
      };

    darwinPkgs = import nixpkgs-darwin {
      system = darwinSystem;
      config = darwinNixpkgsConfig;
      overlays = darwinOverlays;
    };

    darwinPkgsUnstable = unstablePkgsFor darwinSystem;
    darwinPkgsZshFzfTab = import nixpkgs-zsh-fzf-tab {system = darwinSystem;};

    zerobrewVersion = "0.1.2";

    zerobrewZbBin = darwinPkgs.fetchurl {
      url = "https://github.com/lucasgelfond/zerobrew/releases/download/v${zerobrewVersion}/zb-darwin-arm64";
      hash = "sha256-nBIEkj4q06AXbvCujklxDgwpNSEthGp98lvCkHKwJfo=";
    };

    zerobrewZbxBin = darwinPkgs.fetchurl {
      url = "https://github.com/lucasgelfond/zerobrew/releases/download/v${zerobrewVersion}/zbx-darwin-arm64";
      hash = "sha256-jjApD1QHRwQ92u/2jup/9iDFmFQL+TfSMxWpOddsy30=";
    };

    zerobrewPackage = darwinPkgs.stdenvNoCC.mkDerivation {
      pname = "zerobrew";
      version = zerobrewVersion;
      dontUnpack = true;
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        install -m755 ${zerobrewZbBin} "$out/bin/zb"
        install -m755 ${zerobrewZbxBin} "$out/bin/zbx"
        runHook postInstall
      '';
      meta = with darwinPkgs.lib; {
        description = "Fast Homebrew-compatible package installer";
        homepage = "https://github.com/lucasgelfond/zerobrew";
        license = [
          licenses.mit
          licenses.asl20
        ];
        platforms = platforms.darwin;
        mainProgram = "zb";
      };
    };

    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = linuxPkgsFor linuxSystem;
        specialArgs = linuxSpecialArgs linuxSystem;
      };

      aidan-mini = {name, ...}: {
        imports = linuxModules ./hosts/aidan-mini;
        deployment = {
          targetHost = name;
          targetUser = "aidan";
          buildOnTarget = true;
          privilegeEscalationCommand = ["sudo" "-H" "--"];
          tags = ["server" "mini"];
        };
      };

      aidan-nas = {name, ...}: {
        imports = linuxModules ./hosts/aidan-nas;
        deployment = {
          targetHost = name;
          targetUser = "aidan";
          buildOnTarget = true;
          privilegeEscalationCommand = ["sudo" "-H" "--"];
          tags = ["server" "nas"];
        };
      };
    };
  in {
    formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

    checks = forAllSystems (system: {
      treefmt = treefmtEval.${system}.config.build.check self;
    });

    packages = forAllSystems (system: {
      colmena-cli = inputs.colmena.packages.${system}.colmena;
      rotate-amcrest-rtsp-password = rotateAmcrestRtspPasswordFor system;
    });

    apps = forAllSystems (system: {
      rotate-amcrest-rtsp-password = {
        type = "app";
        program = "${self.packages.${system}.rotate-amcrest-rtsp-password}/bin/rotate-amcrest-rtsp-password";
      };
    });

    nixosConfigurations = {
      aidan-nas = mkLinuxHost ./hosts/aidan-nas;
      aidan-mini = mkLinuxHost ./hosts/aidan-mini;
    };

    darwinConfigurations.${darwinHost} = darwin.lib.darwinSystem {
      system = darwinSystem;
      pkgs = darwinPkgs;
      specialArgs = {
        inherit inputs;
        user = darwinUser;
        hostname = darwinHost;
        terminal = darwinTerminal;
      };
      modules = [
        nix-index-database.darwinModules.nix-index
        mac-app-util.darwinModules.default
        ./darwin/default.nix
        (
          {lib, ...}: {
            system.activationScripts.postActivation.text = lib.mkAfter ''
              /bin/mkdir -p /opt/zerobrew

              for dir in store db cache locks bin Cellar; do
                /bin/mkdir -p "/opt/zerobrew/$dir"
              done

              /usr/sbin/chown -R ${darwinUser}:staff /opt/zerobrew
            '';
          }
        )
        {
          system = {
            stateVersion = 5;
            configurationRevision = self.rev or self.dirtyRev or null;
          };
        }
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";
            extraSpecialArgs = {
              inherit inputs stylix;
              terminal = darwinTerminal;
              pkgs-unstable = darwinPkgsUnstable;
              pkgs-zsh-fzf-tab = darwinPkgsZshFzfTab;
            };
            users.${darwinUser} = {
              imports = [
                nixvim.homeModules.nixvim
                stylix.homeModules.stylix
                ./home/darwin.nix
                {
                  home.packages = [zerobrewPackage];

                  home.sessionVariables = {
                    ZEROBREW_ROOT = "/opt/zerobrew";
                    ZEROBREW_PREFIX = "/opt/zerobrew";
                  };

                  home.sessionPath = ["/opt/zerobrew/bin"];
                }
                mac-app-util.homeManagerModules.default
              ];

              home.stateVersion = "25.11";
            };
          };
        }
      ];
    };

    inherit colmenaHive;
    colmena = colmenaHive;

    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = with pkgs;
            [
              age
              pre-commit
              sops
              nixos-anywhere
              treefmtEval.${system}.config.build.wrapper
            ]
            ++ [
              inputs.colmena.packages.${system}.colmena
            ];
        };
      }
    );
  };
}
