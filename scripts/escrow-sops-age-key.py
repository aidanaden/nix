from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, NoReturn

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


ESCROW_KIND = "sops-age-key-escrow"
ESCROW_VERSION = 1
DEFAULT_ACCOUNT = "sops-age"
DEFAULT_SERVICE = "sops-age-key"
DEFAULT_VAULTWARDEN_SERVER = "https://vault.aidanaden.com"
DEFAULT_VAULTWARDEN_NOTE_NAME = "SOPS age key escrow"
DEFAULT_BW_ACCOUNT = "bitwarden-cli"
DEFAULT_BW_CLIENT_ID_SERVICE = "bw-client-id"
DEFAULT_BW_CLIENT_SECRET_SERVICE = "bw-client-secret"


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run(
    args: list[str],
    *,
    input_text: str | None = None,
    capture_output: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=capture_output,
        env=env,
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


def prompt_secret(label: str) -> str:
    value = getpass.getpass(f"{label}: ")
    if not value:
        fail(f"{label} cannot be empty.")
    return value


def load_secret_from_keychain(account: str, service: str) -> str:
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
            "Could not load the secret from macOS Keychain. "
            f"security reported: {detail}"
        )

    value = result.stdout.strip()
    if not value:
        fail(
            f"Keychain entry {account!r}/{service!r} was found but does not contain a value."
        )
    return value


def load_key_from_keychain(account: str, service: str) -> str:
    return ensure_age_secret_key(load_secret_from_keychain(account, service))


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


def render_payload_text(payload: dict[str, Any]) -> str:
    return json.dumps(payload, indent=2) + "\n"


def load_vaultwarden_credential(
    *,
    env_var: str | None,
    keychain_account: str | None,
    keychain_service: str | None,
    prompt_label: str,
) -> str:
    if env_var:
        value = os.environ.get(env_var)
        if value:
            return value

    if keychain_account and keychain_service:
        return load_secret_from_keychain(keychain_account, keychain_service)

    return prompt_secret(prompt_label)


def bw(
    args: list[str],
    *,
    bw_env: dict[str, str],
    session: str | None = None,
    input_text: str | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    command = ["bw", *args]
    if session:
        command.extend(["--session", session])
    return run(command, input_text=input_text, capture_output=capture_output, env=bw_env)


def bw_json(
    args: list[str],
    *,
    bw_env: dict[str, str],
    session: str | None = None,
) -> Any:
    result = bw(args, bw_env=bw_env, session=session, capture_output=True)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail(f"bw returned invalid JSON for {' '.join(args)!r}: {exc}")


def bw_encode(data: dict[str, Any], *, bw_env: dict[str, str]) -> str:
    result = bw(["encode"], bw_env=bw_env, input_text=json.dumps(data), capture_output=True)
    return result.stdout.strip()


def ensure_bw_logged_in(
    *,
    server: str,
    client_id: str,
    client_secret: str,
    password: str,
) -> tuple[dict[str, str], str]:
    appdata_dir = tempfile.mkdtemp(prefix="bw-cli-", dir="/tmp")
    bw_env = os.environ.copy()
    bw_env["BITWARDENCLI_APPDATA_DIR"] = appdata_dir
    bw_env["BW_CLIENTID"] = client_id
    bw_env["BW_CLIENTSECRET"] = client_secret
    bw_env["BW_PASSWORD"] = password

    try:
        bw(["config", "server", server], bw_env=bw_env)
        bw(["login", "--apikey"], bw_env=bw_env)
        session = bw(
            ["unlock", "--passwordenv", "BW_PASSWORD", "--raw"],
            bw_env=bw_env,
            capture_output=True,
        ).stdout.strip()
        if not session:
            fail("bw unlock did not return a session key.")
        bw_env["BW_SESSION"] = session
        bw(["sync"], bw_env=bw_env, session=session)
    except Exception:
        try:
            shutil.rmtree(appdata_dir, ignore_errors=True)
        except Exception:
            pass
        raise

    return bw_env, session


def cleanup_bw_env(bw_env: dict[str, str]) -> None:
    session = bw_env.get("BW_SESSION")
    appdata_dir = bw_env.get("BITWARDENCLI_APPDATA_DIR")
    try:
        if session:
            bw(["lock"], bw_env=bw_env, session=session)
    except Exception:
        pass
    if appdata_dir:
        try:
            shutil.rmtree(appdata_dir, ignore_errors=True)
        except Exception:
            pass


def ensure_folder(folder_name: str, *, bw_env: dict[str, str], session: str) -> str:
    folders = bw_json(["list", "folders"], bw_env=bw_env, session=session)
    matches = [folder for folder in folders if folder.get("name") == folder_name]
    if len(matches) > 1:
        fail(f"Found multiple Vaultwarden folders named {folder_name!r}.")
    if matches:
        folder_id = matches[0].get("id")
        if not folder_id:
            fail(f"Folder {folder_name!r} is missing an id.")
        return str(folder_id)

    created = bw_json(
        ["create", "folder", bw_encode({"name": folder_name}, bw_env=bw_env)],
        bw_env=bw_env,
        session=session,
    )
    folder_id = created.get("id")
    if not folder_id:
        fail(f"Vaultwarden did not return an id for new folder {folder_name!r}.")
    return str(folder_id)


def find_secure_note(
    note_name: str,
    *,
    bw_env: dict[str, str],
    session: str,
) -> dict[str, Any] | None:
    items = bw_json(["list", "items", "--search", note_name], bw_env=bw_env, session=session)
    matches = [
        item
        for item in items
        if item.get("name") == note_name and int(item.get("type", 0)) == 2
    ]
    if len(matches) > 1:
        fail(f"Found multiple secure notes named {note_name!r}.")
    if not matches:
        return None

    item_id = matches[0].get("id")
    if not item_id:
        fail(f"Secure note {note_name!r} is missing an id.")
    return bw_json(["get", "item", str(item_id)], bw_env=bw_env, session=session)


def build_secure_note_item(
    *,
    note_name: str,
    notes: str,
    folder_id: str | None,
    existing_item: dict[str, Any] | None,
    template_item: dict[str, Any],
    template_secure_note: dict[str, Any],
) -> dict[str, Any]:
    item = (
        json.loads(json.dumps(existing_item))
        if existing_item is not None
        else json.loads(json.dumps(template_item))
    )
    item["type"] = 2
    item["name"] = note_name
    item["notes"] = notes
    item["secureNote"] = item.get("secureNote") or json.loads(json.dumps(template_secure_note))
    item["secureNote"]["type"] = 0
    item["folderId"] = folder_id
    item["favorite"] = bool(item.get("favorite", False))
    item["reprompt"] = 1
    return item


def upsert_secure_note(
    *,
    note_name: str,
    notes: str,
    folder_name: str | None,
    bw_env: dict[str, str],
    session: str,
) -> tuple[str, str]:
    folder_id = ensure_folder(folder_name, bw_env=bw_env, session=session) if folder_name else None
    existing = find_secure_note(note_name, bw_env=bw_env, session=session)
    template_item = bw_json(["get", "template", "item"], bw_env=bw_env)
    template_secure_note = bw_json(["get", "template", "item.secureNote"], bw_env=bw_env)
    item = build_secure_note_item(
        note_name=note_name,
        notes=notes,
        folder_id=folder_id,
        existing_item=existing,
        template_item=template_item,
        template_secure_note=template_secure_note,
    )
    encoded = bw_encode(item, bw_env=bw_env)

    if existing is None:
        created = bw_json(["create", "item", encoded], bw_env=bw_env, session=session)
        item_id = created.get("id")
        if not item_id:
            fail(f"Vaultwarden did not return an id for secure note {note_name!r}.")
        return "created", str(item_id)

    edited = bw_json(
        ["edit", "item", str(existing["id"]), encoded],
        bw_env=bw_env,
        session=session,
    )
    item_id = edited.get("id") or existing["id"]
    return "updated", str(item_id)


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


def build_payload_from_args(args: argparse.Namespace) -> dict[str, Any]:
    age_key, source = load_sops_age_key(
        literal_key=args.key,
        key_file=args.key_file,
        account=args.keychain_account,
        service=args.keychain_service,
    )
    passphrase = prompt_passphrase(args.passphrase_env)
    return make_payload(
        age_key=age_key,
        source=source,
        passphrase=passphrase,
        scrypt_n=args.scrypt_n,
        scrypt_r=args.scrypt_r,
        scrypt_p=args.scrypt_p,
    )


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


def store_vaultwarden_command(args: argparse.Namespace) -> int:
    payload = build_payload_from_args(args)
    rendered = render_payload_text(payload)

    client_id = load_vaultwarden_credential(
        env_var=args.bw_client_id_env,
        keychain_account=args.bw_client_id_keychain_account,
        keychain_service=args.bw_client_id_keychain_service,
        prompt_label="Vaultwarden BW client ID",
    )
    client_secret = load_vaultwarden_credential(
        env_var=args.bw_client_secret_env,
        keychain_account=args.bw_client_secret_keychain_account,
        keychain_service=args.bw_client_secret_keychain_service,
        prompt_label="Vaultwarden BW client secret",
    )
    password = load_vaultwarden_credential(
        env_var=args.bw_password_env,
        keychain_account=args.bw_password_keychain_account,
        keychain_service=args.bw_password_keychain_service,
        prompt_label="Vaultwarden master password",
    )

    bw_env, session = ensure_bw_logged_in(
        server=args.server,
        client_id=client_id,
        client_secret=client_secret,
        password=password,
    )

    try:
        action, item_id = upsert_secure_note(
            note_name=args.note_name,
            notes=rendered,
            folder_name=args.folder,
            bw_env=bw_env,
            session=session,
        )
    finally:
        cleanup_bw_env(bw_env)

    print(
        f"{action.title()} secure note {args.note_name!r} on {args.server} "
        f"(id: {item_id}).",
        file=sys.stderr,
    )
    print(
        "Vaultwarden now contains only the encrypted escrow artifact; "
        "the escrow passphrase should remain outside Vaultwarden.",
        file=sys.stderr,
    )
    return 0


def fetch_vaultwarden_command(args: argparse.Namespace) -> int:
    client_id = load_vaultwarden_credential(
        env_var=args.bw_client_id_env,
        keychain_account=args.bw_client_id_keychain_account,
        keychain_service=args.bw_client_id_keychain_service,
        prompt_label="Vaultwarden BW client ID",
    )
    client_secret = load_vaultwarden_credential(
        env_var=args.bw_client_secret_env,
        keychain_account=args.bw_client_secret_keychain_account,
        keychain_service=args.bw_client_secret_keychain_service,
        prompt_label="Vaultwarden BW client secret",
    )
    password = load_vaultwarden_credential(
        env_var=args.bw_password_env,
        keychain_account=args.bw_password_keychain_account,
        keychain_service=args.bw_password_keychain_service,
        prompt_label="Vaultwarden master password",
    )

    bw_env, session = ensure_bw_logged_in(
        server=args.server,
        client_id=client_id,
        client_secret=client_secret,
        password=password,
    )

    try:
        item = find_secure_note(args.note_name, bw_env=bw_env, session=session)
        if item is None:
            fail(
                f"Could not find secure note {args.note_name!r} on {args.server}."
            )
        notes = item.get("notes") or ""
        try:
            payload = json.loads(notes)
        except json.JSONDecodeError as exc:
            fail(
                f"Secure note {args.note_name!r} does not contain valid escrow JSON: {exc}"
            )

        if payload.get("kind") != ESCROW_KIND:
            fail(
                f"Secure note {args.note_name!r} does not contain a {ESCROW_KIND!r} artifact."
            )

        rendered = render_payload_text(payload)
    finally:
        cleanup_bw_env(bw_env)

    if args.output is None:
        sys.stdout.write(rendered)
    else:
        write_private_file(args.output, rendered.rstrip("\n"), force=args.force)
        print(
            f"Wrote escrow artifact from Vaultwarden to {args.output}.",
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

    store_vaultwarden = subparsers.add_parser(
        "store-vaultwarden",
        help="Create an encrypted escrow artifact and upsert it into Vaultwarden as a secure note.",
    )
    store_vaultwarden.add_argument(
        "--server",
        default=DEFAULT_VAULTWARDEN_SERVER,
        help=f"Vaultwarden server URL. Default: {DEFAULT_VAULTWARDEN_SERVER}",
    )
    store_vaultwarden.add_argument(
        "--note-name",
        default=DEFAULT_VAULTWARDEN_NOTE_NAME,
        help=f"Secure note name to create or update. Default: {DEFAULT_VAULTWARDEN_NOTE_NAME!r}",
    )
    store_vaultwarden.add_argument(
        "--folder",
        help="Optional Vaultwarden folder name. Created automatically if missing.",
    )
    store_vaultwarden.add_argument("--key", help="Use this literal age private key instead of auto-discovery.")
    store_vaultwarden.add_argument("--key-file", type=Path, help="Read the age private key from this file.")
    store_vaultwarden.add_argument(
        "--keychain-account",
        default=DEFAULT_ACCOUNT,
        help=f"macOS Keychain account to query for the age key. Default: {DEFAULT_ACCOUNT}",
    )
    store_vaultwarden.add_argument(
        "--keychain-service",
        default=DEFAULT_SERVICE,
        help=f"macOS Keychain service to query for the age key. Default: {DEFAULT_SERVICE}",
    )
    store_vaultwarden.add_argument(
        "--passphrase-env",
        help="Read the escrow passphrase from this environment variable instead of prompting.",
    )
    store_vaultwarden.add_argument("--scrypt-n", type=int, default=32768, help="scrypt N parameter. Default: 32768")
    store_vaultwarden.add_argument("--scrypt-r", type=int, default=8, help="scrypt r parameter. Default: 8")
    store_vaultwarden.add_argument("--scrypt-p", type=int, default=1, help="scrypt p parameter. Default: 1")
    store_vaultwarden.add_argument(
        "--bw-client-id-env",
        default="BW_CLIENTID",
        help="Environment variable holding the Bitwarden API client id. Default: BW_CLIENTID",
    )
    store_vaultwarden.add_argument(
        "--bw-client-secret-env",
        default="BW_CLIENTSECRET",
        help="Environment variable holding the Bitwarden API client secret. Default: BW_CLIENTSECRET",
    )
    store_vaultwarden.add_argument(
        "--bw-password-env",
        default="BW_PASSWORD",
        help="Environment variable holding the vault master password. Default: BW_PASSWORD",
    )
    store_vaultwarden.add_argument(
        "--bw-client-id-keychain-account",
        default=DEFAULT_BW_ACCOUNT,
        help=f"macOS Keychain account for the Bitwarden API client id. Default: {DEFAULT_BW_ACCOUNT}",
    )
    store_vaultwarden.add_argument(
        "--bw-client-id-keychain-service",
        default=DEFAULT_BW_CLIENT_ID_SERVICE,
        help=f"macOS Keychain service for the Bitwarden API client id. Default: {DEFAULT_BW_CLIENT_ID_SERVICE}",
    )
    store_vaultwarden.add_argument(
        "--bw-client-secret-keychain-account",
        default=DEFAULT_BW_ACCOUNT,
        help=f"macOS Keychain account for the Bitwarden API client secret. Default: {DEFAULT_BW_ACCOUNT}",
    )
    store_vaultwarden.add_argument(
        "--bw-client-secret-keychain-service",
        default=DEFAULT_BW_CLIENT_SECRET_SERVICE,
        help=f"macOS Keychain service for the Bitwarden API client secret. Default: {DEFAULT_BW_CLIENT_SECRET_SERVICE}",
    )
    store_vaultwarden.add_argument("--bw-password-keychain-account", help="Optional macOS Keychain account for the vault master password.")
    store_vaultwarden.add_argument("--bw-password-keychain-service", help="Optional macOS Keychain service for the vault master password.")
    store_vaultwarden.set_defaults(func=store_vaultwarden_command)

    fetch_vaultwarden = subparsers.add_parser(
        "fetch-vaultwarden",
        help="Fetch the escrow artifact JSON from a Vaultwarden secure note.",
    )
    fetch_vaultwarden.add_argument(
        "--server",
        default=DEFAULT_VAULTWARDEN_SERVER,
        help=f"Vaultwarden server URL. Default: {DEFAULT_VAULTWARDEN_SERVER}",
    )
    fetch_vaultwarden.add_argument(
        "--note-name",
        default=DEFAULT_VAULTWARDEN_NOTE_NAME,
        help=f"Secure note name to fetch. Default: {DEFAULT_VAULTWARDEN_NOTE_NAME!r}",
    )
    fetch_vaultwarden.add_argument("--output", type=Path, help="Destination file for the fetched escrow JSON.")
    fetch_vaultwarden.add_argument("--force", action="store_true", help="Overwrite an existing output file.")
    fetch_vaultwarden.add_argument(
        "--bw-client-id-env",
        default="BW_CLIENTID",
        help="Environment variable holding the Bitwarden API client id. Default: BW_CLIENTID",
    )
    fetch_vaultwarden.add_argument(
        "--bw-client-secret-env",
        default="BW_CLIENTSECRET",
        help="Environment variable holding the Bitwarden API client secret. Default: BW_CLIENTSECRET",
    )
    fetch_vaultwarden.add_argument(
        "--bw-password-env",
        default="BW_PASSWORD",
        help="Environment variable holding the vault master password. Default: BW_PASSWORD",
    )
    fetch_vaultwarden.add_argument(
        "--bw-client-id-keychain-account",
        default=DEFAULT_BW_ACCOUNT,
        help=f"macOS Keychain account for the Bitwarden API client id. Default: {DEFAULT_BW_ACCOUNT}",
    )
    fetch_vaultwarden.add_argument(
        "--bw-client-id-keychain-service",
        default=DEFAULT_BW_CLIENT_ID_SERVICE,
        help=f"macOS Keychain service for the Bitwarden API client id. Default: {DEFAULT_BW_CLIENT_ID_SERVICE}",
    )
    fetch_vaultwarden.add_argument(
        "--bw-client-secret-keychain-account",
        default=DEFAULT_BW_ACCOUNT,
        help=f"macOS Keychain account for the Bitwarden API client secret. Default: {DEFAULT_BW_ACCOUNT}",
    )
    fetch_vaultwarden.add_argument(
        "--bw-client-secret-keychain-service",
        default=DEFAULT_BW_CLIENT_SECRET_SERVICE,
        help=f"macOS Keychain service for the Bitwarden API client secret. Default: {DEFAULT_BW_CLIENT_SECRET_SERVICE}",
    )
    fetch_vaultwarden.add_argument("--bw-password-keychain-account", help="Optional macOS Keychain account for the vault master password.")
    fetch_vaultwarden.add_argument("--bw-password-keychain-service", help="Optional macOS Keychain service for the vault master password.")
    fetch_vaultwarden.set_defaults(func=fetch_vaultwarden_command)

    return parser


def main() -> int:
    parser = build_parser()
    argv = sys.argv[1:] or ["store-vaultwarden"]
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
