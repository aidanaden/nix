_: {
  users.users.aidan = {
    isNormalUser = true;
    description = "Aidan";
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWNaBcV/KDZBcZhLLZ54DIsJ0pmh1PAo1JeXEakhZmt aidan@aidanaden.com"
    ];
    hashedPassword = null;
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOWNaBcV/KDZBcZhLLZ54DIsJ0pmh1PAo1JeXEakhZmt aidan@aidanaden.com"
  ];

  users.users.appuser = {
    isSystemUser = true;
    group = "users";
    uid = 1001;
    description = "Docker container user";
  };
}
