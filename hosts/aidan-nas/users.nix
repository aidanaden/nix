_: {
  # Main user
  users.users.aidan = {
    isNormalUser = true;
    description = "Aidan";
    extraGroups = [
      "wheel" # sudo
      "docker" # docker access
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWNaBcV/KDZBcZhLLZ54DIsJ0pmh1PAo1JeXEakhZmt aidan@aidanaden.com"
    ];
    # No password - SSH key only
    hashedPassword = null;
  };

  # Allow wheel group to use sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Root user SSH keys (for nixos-anywhere deployment)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWNaBcV/KDZBcZhLLZ54DIsJ0pmh1PAo1JeXEakhZmt aidan@aidanaden.com"
  ];

  # Create appuser for Docker containers (matching OMV setup)
  users.users.appuser = {
    isSystemUser = true;
    group = "users";
    uid = 1001;
    description = "Docker container user";
  };
}
