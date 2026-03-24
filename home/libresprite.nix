{
  pkgs,
  inputs,
  ...
}: let
  stable = import inputs.nixpkgs {
    inherit (pkgs) system;
    config.allowBroken = true;
  };
in {
  home = {
    packages = with pkgs; [
      # sprite editor tool
      stable.libresprite
    ];
  };
}
