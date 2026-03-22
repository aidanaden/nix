{ terminal, ... }:
{
  imports = [
    ./zsh
    ./tmux
    ./bat
    ./git.nix
    ./gh.nix
    ./ssh.nix
    ./jujutsu.nix
    ./btop.nix
    ./yazi.nix
    ./spotify.nix
    ./programs.nix
    ./stylix.nix
    ./kickstart.nixvim/nixvim.nix
    ./helix.nix
    # ./libresprite.nix
  ] ++ (if terminal == "alacritty" then [ ./alacritty.nix ] else [ ./kitty.nix ]);
}
