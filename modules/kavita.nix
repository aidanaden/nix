{config, ...}: {
  services.kavita = {
    enable = true;
    dataDir = "/config/kavita";
    # TokenKey must be 512+ bit — generate with: head -c 64 /dev/urandom | base64 --wrap=0
    # Managed via sops-nix
    tokenKeyFile = config.sops.secrets.kavita_token_key.path;
    settings = {
      Port = 5000;
      IpAddresses = "0.0.0.0,::";
    };
  };

  # Kavita needs access to books/manga on mergerfs
  users.users.kavita.extraGroups = ["users"];

  # Wait for mergerfs
  systemd.services.kavita = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };

  # Sops secret for Kavita token key
  sops.secrets.kavita_token_key = {
    owner = "kavita";
    mode = "0400";
  };
}
