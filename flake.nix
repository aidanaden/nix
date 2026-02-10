{
  description = "NixOS configurations for personal infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
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
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    treefmt-nix,
    disko,
    sops-nix,
    ...
  } @ inputs: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;

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
  in {
    formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

    checks = forAllSystems (system: {
      treefmt = treefmtEval.${system}.config.build.check self;
    });

    nixosConfigurations = {
      aidan-nas = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
          # Make unstable packages available for caddy.withPlugins
          pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/aidan-nas
        ];
      };
    };

    # Development shells for each system
    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.mkShell {
          packages = with pkgs; [
            age
            sops
            nixos-anywhere
            treefmtEval.${system}.config.build.wrapper
          ];
        };
      }
    );
  };
}
