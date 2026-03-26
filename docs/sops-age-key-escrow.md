# SOPS Age Key Escrow

Use Vaultwarden as an encrypted backup location for your `age` private key, not as the live runtime source.

Recommended runtime sources:

- macOS Keychain on your Mac
- `/var/lib/sops-nix/key.txt` on NixOS hosts

Recommended Vaultwarden role:

- store an encrypted escrow artifact as a `Secure Note` or attachment
- keep the escrow passphrase outside Vaultwarden if you want a real recovery boundary

## Create an escrow artifact

From the repo root:

```bash
nix run '.#escrow-sops-age-key' -- backup --output ~/Desktop/sops-age-key-escrow.json
```

The tool will:

- read the current `age` key from `SOPS_AGE_KEY`, a key file, or macOS Keychain
- prompt for a separate escrow passphrase
- write an encrypted JSON artifact

Store that JSON in Vaultwarden:

1. Create a new `Secure Note`
2. Name it something explicit like `SOPS age key escrow`
3. Paste the JSON into the note body, or upload it as an attachment
4. Record where the escrow passphrase is stored

Afterward, remove the local artifact copy if you do not want it lying around:

```bash
rm -f ~/Desktop/sops-age-key-escrow.json
```

## Store directly in Vaultwarden

The repo also supports an autonomous store flow using the Bitwarden CLI against your Vaultwarden server.

Recommended local setup:

- store `BW_CLIENTID` in macOS Keychain as:
  - account: `bitwarden-cli`
  - service: `bw-client-id`
- store `BW_CLIENTSECRET` in macOS Keychain as:
  - account: `bitwarden-cli`
  - service: `bw-client-secret`
- keep the vault master password interactive

The tool uses a temporary isolated `bw` profile, so it does not disturb any existing Bitwarden CLI login on your machine.

With those Keychain entries in place, the default command is:

```bash
nix run '.#escrow-sops-age-key' -- store-vaultwarden
```

That will prompt for:

- the escrow passphrase
- your Bitwarden master password

You can still use environment variables if you want fully noninteractive operation.

Optional folder placement:

```bash
nix run '.#escrow-sops-age-key' -- store-vaultwarden \
  --folder Infrastructure
```

You can override the default server, note name, or folder if you need to:

```bash
nix run '.#escrow-sops-age-key' -- store-vaultwarden \
  --server https://vault.aidanaden.com \
  --note-name 'SOPS age key escrow' \
  --folder Infrastructure
```

## Fetch the escrow artifact from Vaultwarden

```bash
nix run '.#escrow-sops-age-key' -- fetch-vaultwarden \
  --output ~/Downloads/sops-age-key-escrow.json
```

By default, this will use the same Keychain-backed Bitwarden API credentials and then prompt for your Bitwarden master password.

## Restore to a key file

If you need a normal `sops` key file again:

```bash
nix run '.#escrow-sops-age-key' -- restore-file \
  --input ~/Downloads/sops-age-key-escrow.json \
  --output ~/.config/sops/age/keys.txt
```

That writes a `0600` file suitable for `sops`.

## Restore to macOS Keychain

If you want to put the key back into Keychain:

```bash
nix run '.#escrow-sops-age-key' -- restore-keychain \
  --input ~/Downloads/sops-age-key-escrow.json
```

That restores the key under:

- account: `sops-age`
- service: `sops-age-key`

## Migration use

If you are recovering for a host migration, restore to a temp file first:

```bash
nix run '.#escrow-sops-age-key' -- restore-file \
  --input ~/Downloads/sops-age-key-escrow.json \
  --output /tmp/age-key.txt
chmod 600 /tmp/age-key.txt
```

Then continue with the migration flow that copies `/tmp/age-key.txt` into `/var/lib/sops-nix/key.txt`.

## Notes

- The escrow artifact is encrypted with `AES-256-GCM`
- The key-encryption key is derived from your escrow passphrase with `scrypt`
- Vaultwarden should not be the only live source of the key
- Losing both the escrow artifact and the live key source means losing the ability to decrypt `sops` secrets
