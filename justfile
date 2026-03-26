rotate-camera-password *args:
  nix run .#rotate-amcrest-rtsp-password -- {{args}}

escrow-sops-age-key *args:
  nix run '.#escrow-sops-age-key' -- {{args}}
