{ config, pkgs, ... }:

{
  # Main user
  users.users.aidan = {
    isNormalUser = true;
    description = "Aidan";
    extraGroups = [
      "wheel"      # sudo
      "docker"     # docker access
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public keys here
      # Example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... aidan@macbook"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHVhfMVplR5P/ZBaipE8h5VVMb7peVkYNz+VNWK4M4Ow aidan@Aidans-MacBook-Pro.local"
    ];
    # No password - SSH key only
    hashedPassword = null;
  };

  # Allow wheel group to use sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Root user SSH keys (for nixos-anywhere deployment)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHVhfMVplR5P/ZBaipE8h5VVMb7peVkYNz+VNWK4M4Ow aidan@Aidans-MacBook-Pro.local"
  ];

  # Create appuser for Docker containers (matching OMV setup)
  users.users.appuser = {
    isSystemUser = true;
    group = "users";
    uid = 1001;
    description = "Docker container user";
  };
}
