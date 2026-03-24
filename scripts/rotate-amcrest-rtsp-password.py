from __future__ import annotations

import argparse
import getpass
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import NoReturn


class CameraUpdateError(RuntimeError):
    pass


class CameraReachabilityError(CameraUpdateError):
    pass


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    input_text: str | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        input=input_text,
        text=True,
        capture_output=capture_output,
        check=True,
    )


def require_command(command: str) -> None:
    if shutil.which(command) is None:
        fail(f"Missing required command: {command}")


def find_repo_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (
            (candidate / "flake.nix").is_file()
            and (candidate / "secrets" / "secrets.yaml").is_file()
        ):
            return candidate
    fail("Could not find repo root. Run from this repo or pass --repo-root.")


def read_secret_value(secrets_file: Path, key: str) -> str:
    result = run(
        ["sops", "decrypt", "--extract", f'["{key}"]', str(secrets_file)],
        capture_output=True,
    )
    return result.stdout.strip()


def prompt_new_password(username: str) -> str:
    first = getpass.getpass(f"New password for camera user {username}: ")
    second = getpass.getpass("Confirm password: ")

    if not first:
        fail("Password cannot be empty.")
    if first != second:
        fail("Passwords did not match.")

    return first


def update_sops_secret(
    secrets_file: Path,
    username: str,
    password: str,
) -> None:
    with tempfile.TemporaryDirectory(prefix="amcrest-rotate-") as temp_dir:
        temp_path = Path(temp_dir)
        temp_json = temp_path / "secrets.json"
        temp_yaml = temp_path / "secrets.yaml"

        decrypted = run(
            [
                "sops",
                "decrypt",
                "--input-type",
                "yaml",
                "--output-type",
                "json",
                str(secrets_file),
            ],
            capture_output=True,
        )
        data = json.loads(decrypted.stdout)
        data["amcrest_rtsp_user"] = username
        data["amcrest_rtsp_password"] = password
        temp_json.write_text(
            json.dumps(data, indent=2) + "\n",
            encoding="utf-8",
        )

        run(
            [
                "sops",
                "encrypt",
                "--input-type",
                "json",
                "--output-type",
                "yaml",
                "--filename-override",
                str(secrets_file),
                "--output",
                str(temp_yaml),
                str(temp_json),
            ]
        )
        temp_yaml.replace(secrets_file)


def resolve_camera_auth(
    target_user: str,
    current_password: str,
    auth_user: str | None,
) -> tuple[str, str]:
    actual_auth_user = auth_user or target_user
    auth_password = current_password

    if actual_auth_user != target_user:
        auth_password = getpass.getpass(
            f"Password for camera auth user {actual_auth_user}: "
        )
        if not auth_password:
            fail("Camera auth password cannot be empty.")

    return actual_auth_user, auth_password


def build_camera_request_url(
    scheme: str,
    host: str,
    port: int,
    target_user: str,
    current_password: str,
    new_password: str,
) -> str:
    query = urllib.parse.urlencode(
        {
            "action": "modifyPassword",
            "name": target_user,
            "pwd": new_password,
            "pwdOld": current_password,
        }
    )
    return f"{scheme}://{host}:{port}/cgi-bin/userManager.cgi?{query}"


def rotate_camera_password_local(
    scheme: str,
    host: str,
    port: int,
    target_user: str,
    current_password: str,
    new_password: str,
    actual_auth_user: str,
    auth_password: str,
) -> None:
    password_manager = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    base_url = f"{scheme}://{host}:{port}/"
    password_manager.add_password(
        None,
        base_url,
        actual_auth_user,
        auth_password,
    )
    opener = urllib.request.build_opener(
        urllib.request.HTTPDigestAuthHandler(password_manager)
    )
    request_url = build_camera_request_url(
        scheme=scheme,
        host=host,
        port=port,
        target_user=target_user,
        current_password=current_password,
        new_password=new_password,
    )

    try:
        with opener.open(request_url, timeout=10) as response:
            body = response.read().decode("utf-8", errors="replace").strip()
    except urllib.error.HTTPError as exc:
        raise CameraUpdateError(
            f"Camera password update failed: HTTP {exc.code}"
        ) from exc
    except urllib.error.URLError as exc:
        raise CameraReachabilityError(
            f"Camera password update failed: {exc.reason}"
        ) from exc

    if body != "OK":
        raise CameraUpdateError(
            f"Camera password update did not return OK: {body}"
        )


def ssh_prefix(user: str, host: str, ssh_options: list[str]) -> list[str]:
    prefix = ["ssh"]
    for option in ssh_options:
        prefix.extend(["-o", option])
    prefix.append(f"{user}@{host}")
    return prefix


def scp_prefix(ssh_options: list[str]) -> list[str]:
    prefix = ["scp", "-O"]
    for option in ssh_options:
        prefix.extend(["-o", option])
    return prefix


def build_remote_camera_rotation_script(
    *,
    scheme: str,
    host: str,
    port: int,
    target_user: str,
    current_password: str,
    new_password: str,
    actual_auth_user: str,
    auth_password: str,
) -> str:
    payload = {
        "scheme": scheme,
        "host": host,
        "port": port,
        "target_user": target_user,
        "current_password": current_password,
        "new_password": new_password,
        "actual_auth_user": actual_auth_user,
        "auth_password": auth_password,
    }
    payload_json = json.dumps(payload)
    return f"""\
import json
import urllib.error
import urllib.parse
import urllib.request

payload = json.loads({payload_json!r})

password_manager = urllib.request.HTTPPasswordMgrWithDefaultRealm()
base_url = (
    f"{{payload['scheme']}}://{{payload['host']}}:{{payload['port']}}/"
)
password_manager.add_password(
    None,
    base_url,
    payload["actual_auth_user"],
    payload["auth_password"],
)
opener = urllib.request.build_opener(
    urllib.request.HTTPDigestAuthHandler(password_manager)
)
query = urllib.parse.urlencode(
    {{
        "action": "modifyPassword",
        "name": payload["target_user"],
        "pwd": payload["new_password"],
        "pwdOld": payload["current_password"],
    }}
)
request_url = (
    f"{{payload['scheme']}}://{{payload['host']}}:{{payload['port']}}"
    f"/cgi-bin/userManager.cgi?{{query}}"
)

try:
    with opener.open(request_url, timeout=10) as response:
        body = response.read().decode("utf-8", errors="replace").strip()
except urllib.error.HTTPError as exc:
    raise SystemExit(f"Camera password update failed: HTTP {{exc.code}}")
except urllib.error.URLError as exc:
    raise SystemExit(f"Camera password update failed: {{exc.reason}}")

if body != "OK":
    raise SystemExit(f"Camera password update did not return OK: {{body}}")
"""


def rotate_camera_password_via_ssh(
    *,
    scheme: str,
    host: str,
    port: int,
    target_user: str,
    current_password: str,
    new_password: str,
    actual_auth_user: str,
    auth_password: str,
    deploy_host: str,
    deploy_user: str,
    ssh_options: list[str],
) -> None:
    remote_script = build_remote_camera_rotation_script(
        scheme=scheme,
        host=host,
        port=port,
        target_user=target_user,
        current_password=current_password,
        new_password=new_password,
        actual_auth_user=actual_auth_user,
        auth_password=auth_password,
    )
    try:
        run(
            ssh_prefix(deploy_user, deploy_host, ssh_options)
            + ["sudo", "docker", "exec", "-i", "frigate", "python3", "-"],
            input_text=remote_script,
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        if detail:
            raise CameraUpdateError(detail) from exc
        raise CameraUpdateError(
            f"Camera password update via {deploy_user}@{deploy_host} failed."
        ) from exc


def rotate_camera_password(
    *,
    scheme: str,
    host: str,
    port: int,
    target_user: str,
    current_password: str,
    new_password: str,
    auth_user: str | None,
    deploy_host: str,
    deploy_user: str,
    ssh_options: list[str],
) -> str:
    actual_auth_user, auth_password = resolve_camera_auth(
        target_user=target_user,
        current_password=current_password,
        auth_user=auth_user,
    )
    try:
        rotate_camera_password_local(
            scheme=scheme,
            host=host,
            port=port,
            target_user=target_user,
            current_password=current_password,
            new_password=new_password,
            actual_auth_user=actual_auth_user,
            auth_password=auth_password,
        )
        return "local network"
    except CameraReachabilityError as exc:
        print(
            (
                f"{exc}. Retrying via {deploy_user}@{deploy_host}, "
                "which should be on the same LAN as the camera."
            ),
            file=sys.stderr,
        )
        rotate_camera_password_via_ssh(
            scheme=scheme,
            host=host,
            port=port,
            target_user=target_user,
            current_password=current_password,
            new_password=new_password,
            actual_auth_user=actual_auth_user,
            auth_password=auth_password,
            deploy_host=deploy_host,
            deploy_user=deploy_user,
            ssh_options=ssh_options,
        )
        return f"{deploy_user}@{deploy_host}"


def deploy(
    repo_root: Path,
    secrets_file: Path,
    deploy_revision: str,
    deploy_host: str,
    deploy_user: str,
    deploy_system: str,
    ssh_options: list[str],
) -> None:
    workspace_name = f"rotate-amcrest-{uuid.uuid4().hex[:8]}"
    workspace_dir = Path(tempfile.mkdtemp(prefix="rotate-amcrest-workspace."))
    remote_dir = f"/home/{deploy_user}/{workspace_dir.name}"

    try:
        run(
            [
                "jj",
                "workspace",
                "add",
                "--name",
                workspace_name,
                "-r",
                deploy_revision,
                str(workspace_dir),
            ],
            cwd=repo_root,
        )

        workspace_secrets = workspace_dir / "secrets" / "secrets.yaml"
        workspace_secrets.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(secrets_file, workspace_secrets)

        run(
            [
                "nix",
                "eval",
                "--raw",
                (
                    ".#nixosConfigurations."
                    f"{deploy_system}.config.system.build.toplevel.drvPath"
                ),
            ],
            cwd=workspace_dir,
        )

        run(
            ssh_prefix(deploy_user, deploy_host, ssh_options)
            + ["rm", "-rf", remote_dir]
        )
        run(
            scp_prefix(ssh_options)
            + [
                "-r",
                str(workspace_dir),
                f"{deploy_user}@{deploy_host}:/home/{deploy_user}/",
            ]
        )
        run(
            ssh_prefix(deploy_user, deploy_host, ssh_options)
            + [
                "sudo",
                "nixos-rebuild",
                "switch",
                "--flake",
                f"{remote_dir}#{deploy_system}",
            ]
        )

        verify_script = """\
import json
import urllib.request

with urllib.request.urlopen(
    "http://127.0.0.1:1984/api/streams",
    timeout=5,
) as response:
    data = json.load(response)

for name in ("studio_main", "studio_sub"):
    entry = data.get(name, {})
    if not entry.get("producers"):
        raise SystemExit(f"{name}: no live producer after deploy")

print("Frigate streams are live.")
"""
        run(
            ssh_prefix(deploy_user, deploy_host, ssh_options)
            + ["sudo", "docker", "exec", "-i", "frigate", "python3", "-"],
            input_text=verify_script,
        )
    finally:
        try:
            run(
                ssh_prefix(deploy_user, deploy_host, ssh_options)
                + ["rm", "-rf", remote_dir]
            )
        except subprocess.CalledProcessError:
            pass

        shutil.rmtree(workspace_dir, ignore_errors=True)

        try:
            run(["jj", "workspace", "forget", workspace_name], cwd=repo_root)
        except subprocess.CalledProcessError:
            pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="rotate-amcrest-rtsp-password",
        description=(
            "Rotate the Amcrest RTSP password, update sops, "
            "and optionally deploy aidan-mini. "
            "By default, the camera password is updated over the "
            "Amcrest API, with automatic SSH fallback via the "
            "deploy host if the local machine cannot reach the camera."
        )
    )
    parser.add_argument(
        "--manual-camera",
        action="store_true",
        help=(
            "Do not call the Amcrest API. "
            "Pause for a manual password change in the camera UI instead."
        ),
    )
    parser.add_argument(
        "--update-camera",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="Deploy aidan-mini after updating the secret.",
    )
    parser.add_argument(
        "--camera-host",
        default="192.168.1.5",
        help="Camera host. Default: 192.168.1.5",
    )
    parser.add_argument(
        "--camera-port",
        default=80,
        type=int,
        help="Camera HTTP port. Default: 80",
    )
    parser.add_argument(
        "--camera-scheme",
        default="http",
        help="Camera scheme. Default: http",
    )
    parser.add_argument(
        "--camera-auth-user",
        help=(
            "Auth user for camera API rotation. "
            "Default: current RTSP user"
        ),
    )
    parser.add_argument(
        "--deploy-host",
        default="aidan-mini",
        help=(
            "SSH host for deployment and camera API fallback. "
            "Default: aidan-mini"
        ),
    )
    parser.add_argument(
        "--deploy-user",
        default="aidan",
        help="SSH user for deployment. Default: aidan",
    )
    parser.add_argument(
        "--deploy-system",
        default="aidan-mini",
        help="Flake host name to rebuild. Default: aidan-mini",
    )
    parser.add_argument(
        "--deploy-revision",
        default="main",
        help="jj revision to deploy from. Default: main",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        help="Override repo root detection.",
    )
    parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        help="Extra ssh/scp -o option. Repeat as needed.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    for command in ["jj", "nix", "scp", "sops", "ssh"]:
        require_command(command)

    if args.repo_root:
        repo_root = args.repo_root.resolve()
    else:
        repo_root = find_repo_root(Path.cwd().resolve())
    secrets_file = repo_root / "secrets" / "secrets.yaml"

    if not secrets_file.is_file():
        fail(f"Secrets file not found: {secrets_file}")

    rtsp_user = read_secret_value(secrets_file, "amcrest_rtsp_user")
    current_password = read_secret_value(secrets_file, "amcrest_rtsp_password")
    new_password = prompt_new_password(rtsp_user)

    if new_password == current_password:
        fail(
            "New password matches the current stored password. "
            "Nothing to do."
        )

    if args.manual_camera:
        input(
            f"Change the {rtsp_user} password in the camera UI now, "
            "then press Enter to continue."
        )
    else:
        rotation_path = rotate_camera_password(
            scheme=args.camera_scheme,
            host=args.camera_host,
            port=args.camera_port,
            target_user=rtsp_user,
            current_password=current_password,
            new_password=new_password,
            auth_user=args.camera_auth_user,
            deploy_host=args.deploy_host,
            deploy_user=args.deploy_user,
            ssh_options=args.ssh_option,
        )
        print(
            f"Camera password updated over API for user {rtsp_user} "
            f"via {rotation_path}."
        )

    update_sops_secret(secrets_file, rtsp_user, new_password)
    print(f"Updated amcrest_rtsp_password in {secrets_file}.")

    if args.deploy:
        deploy(
            repo_root=repo_root,
            secrets_file=secrets_file,
            deploy_revision=args.deploy_revision,
            deploy_host=args.deploy_host,
            deploy_user=args.deploy_user,
            deploy_system=args.deploy_system,
            ssh_options=args.ssh_option,
        )
        print(
            f"Deployed {args.deploy_system} from revision "
            f"{args.deploy_revision}."
        )
    else:
        print(
            f"Local secret updated. Redeploy {args.deploy_system} when ready."
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
