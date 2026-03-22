{
  pkgs,
  inputs,
  terminal,
  ...
}:
let
  stable = import inputs.nixpkgs {
    system = pkgs.system;
    config.allowBroken = true;
  };
in
{
  home = {
    packages = with pkgs; [
      # sprite editor tool
      stable.libresprite
    ];
  };
}
