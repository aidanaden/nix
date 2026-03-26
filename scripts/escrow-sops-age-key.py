from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


ESCROW_KIND = "sops-age-key-escrow"
ESCROW_VERSION = 1
DEFAULT_ACCOUNT = "sops-age"
DEFAULT_SERVICE = "sops-age-key"


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run(
    args: list[str],
    *,
    input_text: str | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=capture_output,
        check=True,
    )


def ensure_age_secret_key(value: str) -> str:
    candidate = value.strip()
    if not candidate.startswith("AGE-SECRET-KEY-"):
        fail("The supplied value is not an age private key.")
    return candidate


def extract_age_secret_key(text: str) -> str | None:
    for line in text.splitlines():
        candidate = line.strip()
        if candidate.startswith("AGE-SECRET-KEY-"):
            return candidate
    return None


def prompt_passphrase(passphrase_env: str | None) -> str:
    if passphrase_env:
        value = os.environ.get(passphrase_env)
        if not value:
            fail(f"Environment variable {passphrase_env!r} is empty or unset.")
        return value

    first = getpass.getpass("Escrow passphrase: ")
    second = getpass.getpass("Confirm escrow passphrase: ")

    if not first:
        fail("Escrow passphrase cannot be empty.")
    if first != second:
        fail("Escrow passphrases did not match.")
    return first


def prompt_restore_passphrase(passphrase_env: str | None) -> str:
    if passphrase_env:
        value = os.environ.get(passphrase_env)
        if not value:
            fail(f"Environment variable {passphrase_env!r} is empty or unset.")
        return value
    return getpass.getpass("Escrow passphrase: ")


def load_key_from_keychain(account: str, service: str) -> str:
    if sys.platform != "darwin":
        fail("Keychain lookup is only available on macOS.")

    try:
        result = run(
            [
                "security",
                "find-generic-password",
                "-a",
                account,
                "-s",
                service,
                "-w",
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or "security lookup failed"
        fail(
            "Could not load the age key from macOS Keychain. "
            f"security reported: {detail}"
        )

    return ensure_age_secret_key(result.stdout)


def load_sops_age_key(
    *,
    literal_key: str | None,
    key_file: Path | None,
    account: str,
    service: str,
) -> tuple[str, str]:
    if literal_key:
        return ensure_age_secret_key(literal_key), "argument"

    if key_file is not None:
        if not key_file.is_file():
            fail(f"Key file not found: {key_file}")
        key = extract_age_secret_key(key_file.read_text())
        if key is None:
            fail(f"Could not find an age private key in {key_file}.")
        return ensure_age_secret_key(key), f"file:{key_file}"

    env_key = os.environ.get("SOPS_AGE_KEY")
    if env_key:
        return ensure_age_secret_key(env_key), "env:SOPS_AGE_KEY"

    default_paths = [
        Path.home() / ".config" / "sops" / "age" / "keys.txt",
        Path.home() / ".config" / "age" / "keys.txt",
        Path("/var/lib/sops-nix/key.txt"),
    ]

    for candidate in default_paths:
        if candidate.is_file():
            key = extract_age_secret_key(candidate.read_text())
            if key is not None:
                return ensure_age_secret_key(key), f"file:{candidate}"

    if sys.platform == "darwin":
        return load_key_from_keychain(account, service), "macos-keychain"

    fail(
        "Could not find an age private key. "
        "Export SOPS_AGE_KEY, pass --key-file, or make a key file available."
    )


def b64encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def b64decode(value: str) -> bytes:
    try:
        return base64.b64decode(value.encode("ascii"))
    except Exception as exc:
        fail(f"Invalid base64 payload: {exc}")


def derive_kek(passphrase: str, salt: bytes, *, n: int, r: int, p: int) -> bytes:
    maxmem = 128 * 1024 * 1024
    return hashlib.scrypt(
        passphrase.encode("utf-8"),
        salt=salt,
        n=n,
        r=r,
        p=p,
        maxmem=maxmem,
        dklen=32,
    )


def make_payload(
    *,
    age_key: str,
    source: str,
    passphrase: str,
    scrypt_n: int,
    scrypt_r: int,
    scrypt_p: int,
) -> dict[str, Any]:
    salt = os.urandom(16)
    nonce = os.urandom(12)
    aad = f"{ESCROW_KIND}:v{ESCROW_VERSION}".encode("utf-8")
    kek = derive_kek(passphrase, salt, n=scrypt_n, r=scrypt_r, p=scrypt_p)
    ciphertext = AESGCM(kek).encrypt(nonce, age_key.encode("utf-8"), aad)
    return {
        "kind": ESCROW_KIND,
        "version": ESCROW_VERSION,
        "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "metadata": {
            "source": source,
            "hostname": platform.node(),
            "key_type": "age",
        },
        "aad": aad.decode("utf-8"),
        "kdf": {
            "name": "scrypt",
            "n": scrypt_n,
            "r": scrypt_r,
            "p": scrypt_p,
            "salt_b64": b64encode(salt),
        },
        "cipher": {
            "name": "AES-256-GCM",
            "nonce_b64": b64encode(nonce),
        },
        "ciphertext_b64": b64encode(ciphertext),
    }


def load_payload(path: Path) -> dict[str, Any]:
    if not path.is_file():
        fail(f"Escrow artifact not found: {path}")
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        fail(f"Could not parse escrow artifact JSON: {exc}")

    if payload.get("kind") != ESCROW_KIND:
        fail("The supplied file is not a SOPS age key escrow artifact.")
    if payload.get("version") != ESCROW_VERSION:
        fail(
            f"Unsupported escrow artifact version {payload.get('version')!r}. "
            f"Expected {ESCROW_VERSION}."
        )
    return payload


def decrypt_payload(payload: dict[str, Any], passphrase: str) -> str:
    kdf = payload.get("kdf", {})
    cipher = payload.get("cipher", {})
    aad = payload.get("aad")
    if not isinstance(aad, str):
        fail("Escrow artifact is missing a valid AAD value.")

    salt = b64decode(kdf["salt_b64"])
    nonce = b64decode(cipher["nonce_b64"])
    ciphertext = b64decode(payload["ciphertext_b64"])

    try:
        kek = derive_kek(
            passphrase,
            salt,
            n=int(kdf["n"]),
            r=int(kdf["r"]),
            p=int(kdf["p"]),
        )
        plaintext = AESGCM(kek).decrypt(nonce, ciphertext, aad.encode("utf-8"))
    except Exception as exc:
        fail(f"Could not decrypt escrow artifact. Wrong passphrase or corrupt data: {exc}")

    return ensure_age_secret_key(plaintext.decode("utf-8"))


def write_private_file(path: Path, content: str, *, force: bool) -> None:
    if path.exists() and not force:
        fail(f"Refusing to overwrite existing file without --force: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content + "\n")
    path.chmod(0o600)


def backup_command(args: argparse.Namespace) -> int:
    age_key, source = load_sops_age_key(
        literal_key=args.key,
        key_file=args.key_file,
        account=args.keychain_account,
        service=args.keychain_service,
    )
    passphrase = prompt_passphrase(args.passphrase_env)
    payload = make_payload(
        age_key=age_key,
        source=source,
        passphrase=passphrase,
        scrypt_n=args.scrypt_n,
        scrypt_r=args.scrypt_r,
        scrypt_p=args.scrypt_p,
    )
    rendered = json.dumps(payload, indent=2) + "\n"

    if args.output is None:
        sys.stdout.write(rendered)
    else:
        write_private_file(args.output, rendered.rstrip("\n"), force=args.force)
        print(
            f"Wrote encrypted escrow artifact to {args.output}. "
            "Store that JSON in a Vaultwarden Secure Note or attachment.",
            file=sys.stderr,
        )

    print(
        "Keep the escrow passphrase outside Vaultwarden if you want a real recovery boundary.",
        file=sys.stderr,
    )
    return 0


def restore_file_command(args: argparse.Namespace) -> int:
    payload = load_payload(args.input)
    passphrase = prompt_restore_passphrase(args.passphrase_env)
    age_key = decrypt_payload(payload, passphrase)
    write_private_file(args.output, age_key, force=args.force)
    print(f"Restored age key to {args.output}.", file=sys.stderr)
    return 0


def restore_keychain_command(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        fail("Keychain restore is only available on macOS.")

    payload = load_payload(args.input)
    passphrase = prompt_restore_passphrase(args.passphrase_env)
    age_key = decrypt_payload(payload, passphrase)

    run(
        [
            "security",
            "add-generic-password",
            "-U",
            "-a",
            args.keychain_account,
            "-s",
            args.keychain_service,
            "-w",
            age_key,
        ]
    )
    print(
        "Restored age key into macOS Keychain "
        f"({args.keychain_account}/{args.keychain_service}).",
        file=sys.stderr,
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Create and recover an encrypted escrow artifact for the SOPS age private key. "
            "The generated JSON is intended for storage in Vaultwarden as backup, not as a live runtime source."
        )
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    backup = subparsers.add_parser(
        "backup",
        help="Create an encrypted escrow artifact from the current SOPS age key.",
    )
    backup.add_argument("--output", type=Path, help="Where to write the encrypted JSON artifact.")
    backup.add_argument("--force", action="store_true", help="Overwrite an existing output file.")
    backup.add_argument("--key", help="Use this literal age private key instead of auto-discovery.")
    backup.add_argument("--key-file", type=Path, help="Read the age private key from this file.")
    backup.add_argument(
        "--keychain-account",
        default=DEFAULT_ACCOUNT,
        help=f"macOS Keychain account to query. Default: {DEFAULT_ACCOUNT}",
    )
    backup.add_argument(
        "--keychain-service",
        default=DEFAULT_SERVICE,
        help=f"macOS Keychain service to query. Default: {DEFAULT_SERVICE}",
    )
    backup.add_argument(
        "--passphrase-env",
        help="Read the escrow passphrase from this environment variable instead of prompting.",
    )
    backup.add_argument("--scrypt-n", type=int, default=32768, help="scrypt N parameter. Default: 32768")
    backup.add_argument("--scrypt-r", type=int, default=8, help="scrypt r parameter. Default: 8")
    backup.add_argument("--scrypt-p", type=int, default=1, help="scrypt p parameter. Default: 1")
    backup.set_defaults(func=backup_command)

    restore_file = subparsers.add_parser(
        "restore-file",
        help="Decrypt an escrow artifact back into a private key file.",
    )
    restore_file.add_argument("--input", required=True, type=Path, help="Escrow artifact JSON to decrypt.")
    restore_file.add_argument("--output", required=True, type=Path, help="Destination key file path.")
    restore_file.add_argument("--force", action="store_true", help="Overwrite an existing output file.")
    restore_file.add_argument(
        "--passphrase-env",
        help="Read the escrow passphrase from this environment variable instead of prompting.",
    )
    restore_file.set_defaults(func=restore_file_command)

    restore_keychain = subparsers.add_parser(
        "restore-keychain",
        help="Decrypt an escrow artifact and import the key into macOS Keychain.",
    )
    restore_keychain.add_argument("--input", required=True, type=Path, help="Escrow artifact JSON to decrypt.")
    restore_keychain.add_argument(
        "--keychain-account",
        default=DEFAULT_ACCOUNT,
        help=f"macOS Keychain account to write. Default: {DEFAULT_ACCOUNT}",
    )
    restore_keychain.add_argument(
        "--keychain-service",
        default=DEFAULT_SERVICE,
        help=f"macOS Keychain service to write. Default: {DEFAULT_SERVICE}",
    )
    restore_keychain.add_argument(
        "--passphrase-env",
        help="Read the escrow passphrase from this environment variable instead of prompting.",
    )
    restore_keychain.set_defaults(func=restore_keychain_command)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
