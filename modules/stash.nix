_: let
  mergerfsDeps = {
    after = ["mergerfs.service"];
    requires = ["mergerfs.service"];
  };
in {
  # Stash is unstable-only in nixpkgs. Use OCI container until 25.05+
  # when services.stash becomes available on stable.

  virtualisation.oci-containers.containers.stash = {
    image = "stashapp/stash:v0.30.1";
    ports = ["127.0.0.1:9999:9999"];
    volumes = [
      "/config/stash:/root/.stash"
      "/data/shared/media/ncdata/photos/sensitive-legalese:/data:ro"
      "/config/stash/generated:/generated"
    ];
    environment = {
      STASH_EXTERNAL_HOST = "https://stash.aidanaden.com";
    };
    extraOptions = [
      "--name=stash"
      "--memory=4g"
      "--cpus=2"
    ];
  };

  # Wait for mergerfs
  systemd.services.docker-stash = mergerfsDeps;
}
