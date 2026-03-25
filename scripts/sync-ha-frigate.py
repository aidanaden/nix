# flake8: noqa
from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from typing import Any, NoReturn


REMOTE_SCRIPT = r"""
from __future__ import annotations

import argparse
import json
import secrets
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NoReturn


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def api(
    base_url: str,
    token: str,
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
) -> Any:
    headers = {"Authorization": f"Bearer {token}"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode()
    request = urllib.request.Request(
        base_url + path,
        headers=headers,
        data=data,
        method=method,
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def get_access_token(base_url: str, ha_user_name: str, client_id: str) -> str:
    auth = json.loads(Path("/config/.storage/auth").read_text())

    user_id = next(
        (
            user["id"]
            for user in auth["data"]["users"]
            if user.get("name") == ha_user_name
        ),
        None,
    )
    if user_id is None:
        fail(f"Could not find Home Assistant user {ha_user_name!r}.")

    refresh_token = next(
        (
            token["token"]
            for token in auth["data"]["refresh_tokens"]
            if token.get("user_id") == user_id
            and token.get("token_type") == "normal"
            and token.get("client_id") == client_id
        ),
        None,
    )
    if refresh_token is None:
        fail(
            "Could not find a matching Home Assistant refresh token. "
            "Sign into Home Assistant at least once from the configured client ID first."
        )

    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": client_id,
        }
    ).encode()
    request = urllib.request.Request(
        base_url + "/auth/token",
        data=body,
        method="POST",
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)["access_token"]


def create_flow_entry(
    base_url: str,
    token: str,
    handler: str,
    step_payload: dict[str, Any],
) -> dict[str, Any]:
    flow = api(
        base_url,
        token,
        "POST",
        "/api/config/config_entries/flow",
        {"handler": handler},
    )
    result = api(
        base_url,
        token,
        "POST",
        f"/api/config/config_entries/flow/{flow['flow_id']}",
        step_payload,
    )
    if result.get("type") != "create_entry":
        fail(f"Unexpected {handler} flow result: {json.dumps(result)}")
    return result["result"]


def load_config_entry_from_storage(entry_id: str) -> dict[str, Any]:
    config_entries = json.loads(
        Path("/config/.storage/core.config_entries").read_text()
    )
    entry = next(
        (
            item
            for item in config_entries["data"]["entries"]
            if item.get("entry_id") == entry_id
        ),
        None,
    )
    if entry is None:
        fail(f"Could not find config entry {entry_id!r} in Home Assistant storage.")
    return entry


def insert_alarmo_entry_in_storage() -> dict[str, Any]:
    config_entries_path = Path("/config/.storage/core.config_entries")
    config_entries = json.loads(config_entries_path.read_text())
    now = __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc
    ).isoformat(timespec="microseconds")
    entry = {
        "created_at": now,
        "data": {},
        "disabled_by": None,
        "discovery_keys": {},
        "domain": "alarmo",
        "entry_id": secrets.token_hex(13).upper(),
        "minor_version": 1,
        "modified_at": now,
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "subentries": [],
        "title": "Alarmo",
        "unique_id": secrets.token_hex(6),
        "version": 1,
    }
    config_entries["data"]["entries"].append(entry)
    config_entries_path.write_text(json.dumps(config_entries, separators=(",", ":")))
    return entry


def sync_frigate_options(
    base_url: str,
    token: str,
    frigate_entry: dict[str, Any],
    rtsp_url_template: str,
) -> dict[str, Any]:
    storage_entry = load_config_entry_from_storage(frigate_entry["entry_id"])
    current_options = dict(storage_entry.get("options", {}))
    desired_options = {
        "enable_webrtc": current_options.get("enable_webrtc", False),
        "rtsp_url_template": rtsp_url_template,
        "notification_proxy_enable": current_options.get(
            "notification_proxy_enable", True
        ),
        "media_browser_enable": current_options.get(
            "media_browser_enable", True
        ),
        "notification_proxy_expire_after_seconds": current_options.get(
            "notification_proxy_expire_after_seconds", 0
        ),
    }

    if current_options == desired_options:
        return {
            "changed": False,
            "options": current_options,
        }

    flow = api(
        base_url,
        token,
        "POST",
        "/api/config/config_entries/options/flow",
        {
            "handler": frigate_entry["entry_id"],
            "show_advanced_options": True,
        },
    )
    if flow.get("type") != "form":
        fail(f"Unexpected Frigate options flow result: {json.dumps(flow)}")

    result = api(
        base_url,
        token,
        "POST",
        f"/api/config/config_entries/options/flow/{flow['flow_id']}",
        desired_options,
    )
    if result.get("type") != "create_entry":
        fail(f"Unexpected Frigate options update result: {json.dumps(result)}")

    return {
        "changed": True,
        "options": desired_options,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Ensure Home Assistant MQTT + Frigate entries exist "
            "and prefer the high-quality Frigate live stream."
        )
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8123")
    parser.add_argument("--ha-user-name", default="aidan")
    parser.add_argument("--client-id", default="https://ha.aidanaden.com/")
    parser.add_argument("--mqtt-broker", default="mqtt")
    parser.add_argument("--mqtt-port", type=int, default=1883)
    parser.add_argument("--frigate-url", default="http://frigate:5000")
    parser.add_argument("--frigate-validate-ssl", action="store_true")
    parser.add_argument("--frigate-username", default="")
    parser.add_argument("--frigate-password", default="")
    parser.add_argument(
        "--rtsp-url-template",
        default="rtsp://frigate:8554/{{ name }}_main",
    )
    parser.add_argument("--skip-mqtt", action="store_true")
    parser.add_argument("--skip-alarmo", action="store_true")
    args = parser.parse_args()

    token = get_access_token(args.base_url, args.ha_user_name, args.client_id)
    handlers = api(
        base_url=args.base_url,
        token=token,
        method="GET",
        path="/api/config/config_entries/flow_handlers",
    )

    entries = api(
        base_url=args.base_url,
        token=token,
        method="GET",
        path="/api/config/config_entries/entry",
    )

    mqtt_entry = next(
        (entry for entry in entries if entry.get("domain") == "mqtt"),
        None,
    )
    frigate_entry = next(
        (entry for entry in entries if entry.get("domain") == "frigate"), None
    )
    alarmo_entry = next(
        (entry for entry in entries if entry.get("domain") == "alarmo"), None
    )

    summary: dict[str, Any] = {
        "mqtt": None,
        "frigate": None,
        "frigate_options": None,
        "alarmo": None,
    }

    if not args.skip_mqtt:
        if mqtt_entry is None:
            if "mqtt" not in handlers:
                fail("Home Assistant MQTT flow handler is unavailable.")
            mqtt_entry = create_flow_entry(
                args.base_url,
                token,
                "mqtt",
                {
                    "broker": args.mqtt_broker,
                    "port": args.mqtt_port,
                    "username": "",
                    "password": "",
                },
            )
            summary["mqtt"] = {
                "created": True,
                "entry_id": mqtt_entry["entry_id"],
            }
        else:
            summary["mqtt"] = {
                "created": False,
                "entry_id": mqtt_entry["entry_id"],
            }

    if frigate_entry is None:
        if "frigate" not in handlers:
            fail(
                "Home Assistant Frigate flow handler is unavailable. "
                "Install the Frigate custom component first."
            )
        frigate_entry = create_flow_entry(
            args.base_url,
            token,
            "frigate",
            {
                "url": args.frigate_url,
                "validate_ssl": args.frigate_validate_ssl,
                "username": args.frigate_username,
                "password": args.frigate_password,
            },
        )
        summary["frigate"] = {
            "created": True,
            "entry_id": frigate_entry["entry_id"],
        }
    else:
        summary["frigate"] = {
            "created": False,
            "entry_id": frigate_entry["entry_id"],
        }

    if args.skip_alarmo:
        summary["alarmo"] = {
            "skipped": True,
        }
    elif alarmo_entry is None:
        if "alarmo" in handlers:
            alarmo_entry = create_flow_entry(
                args.base_url,
                token,
                "alarmo",
                {},
            )
            summary["alarmo"] = {
                "created": True,
                "entry_id": alarmo_entry["entry_id"],
                "method": "config_flow",
                "requires_restart": False,
            }
        else:
            alarmo_entry = insert_alarmo_entry_in_storage()
            summary["alarmo"] = {
                "created": True,
                "entry_id": alarmo_entry["entry_id"],
                "method": "storage_fallback",
                "requires_restart": True,
            }
    else:
        summary["alarmo"] = {
            "created": False,
            "entry_id": alarmo_entry["entry_id"],
            "requires_restart": False,
        }

    summary["frigate_options"] = sync_frigate_options(
        args.base_url,
        token,
        frigate_entry,
        args.rtsp_url_template,
    )

    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
"""


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
        text=True,
        input=input_text,
        capture_output=capture_output,
        check=True,
    )


def require_command(command: str) -> None:
    if shutil.which(command) is None:
        fail(f"Missing required command: {command}")


def ssh_prefix(user: str, host: str, ssh_options: list[str]) -> list[str]:
    prefix = ["ssh"]
    for option in ssh_options:
        prefix.extend(["-o", option])
    prefix.append(f"{user}@{host}")
    return prefix


def build_remote_command(args: argparse.Namespace) -> list[str]:
    remote_command = [
        "sudo",
        "docker",
        "exec",
        "-i",
        args.homeassistant_container_name,
        "python",
        "-",
        "--ha-user-name",
        args.ha_user_name,
        "--client-id",
        args.client_id,
        "--mqtt-broker",
        args.mqtt_broker,
        "--mqtt-port",
        str(args.mqtt_port),
        "--frigate-url",
        args.frigate_url,
        "--rtsp-url-template",
        args.rtsp_url_template,
    ]
    if args.frigate_validate_ssl:
        remote_command.append("--frigate-validate-ssl")
    if args.frigate_username:
        remote_command.extend(["--frigate-username", args.frigate_username])
    if args.frigate_password:
        remote_command.extend(["--frigate-password", args.frigate_password])
    if args.skip_mqtt:
        remote_command.append("--skip-mqtt")
    if args.skip_alarmo:
        remote_command.append("--skip-alarmo")
    command = ssh_prefix(args.deploy_user, args.deploy_host, args.ssh_option)
    command.append(shlex.join(remote_command))
    return command


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sync Home Assistant's MQTT, Frigate, and Alarmo integrations "
            "so HA uses the high-quality Frigate main stream."
        )
    )
    parser.add_argument("--deploy-user", default="aidan")
    parser.add_argument("--deploy-host", default="aidan-mini")
    parser.add_argument(
        "--homeassistant-container-name",
        default="homeassistant",
    )
    parser.add_argument("--ha-user-name", default="aidan")
    parser.add_argument("--client-id", default="https://ha.aidanaden.com/")
    parser.add_argument("--mqtt-broker", default="mqtt")
    parser.add_argument("--mqtt-port", type=int, default=1883)
    parser.add_argument("--frigate-url", default="http://frigate:5000")
    parser.add_argument("--frigate-validate-ssl", action="store_true")
    parser.add_argument("--frigate-username", default="")
    parser.add_argument("--frigate-password", default="")
    parser.add_argument(
        "--rtsp-url-template",
        default="rtsp://frigate:8554/{{ name }}_main",
    )
    parser.add_argument("--skip-mqtt", action="store_true")
    parser.add_argument("--skip-alarmo", action="store_true")
    parser.add_argument(
        "--ssh-option",
        action="append",
        default=[],
        help="Additional ssh -o option, repeatable.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    require_command("ssh")

    try:
        result = run(
            build_remote_command(args),
            input_text=REMOTE_SCRIPT,
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        if exc.stdout:
            print(exc.stdout.strip(), file=sys.stderr)
        if exc.stderr:
            print(exc.stderr.strip(), file=sys.stderr)
        raise SystemExit(exc.returncode) from exc

    output = result.stdout.strip()
    if not output:
        fail("Sync script did not return JSON output.")
    print(output)

    try:
        summary = json.loads(output)
    except json.JSONDecodeError as exc:
        fail(f"Sync script returned invalid JSON: {exc}")

    if summary.get("alarmo", {}).get("requires_restart"):
        restart_command = ssh_prefix(args.deploy_user, args.deploy_host, args.ssh_option)
        restart_command.append("sudo systemctl restart docker-homeassistant.service")
        run(restart_command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
