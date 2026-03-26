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


def load_alarmo_storage() -> dict[str, Any] | None:
    storage_path = Path("/config/.storage/alarmo.storage")
    if not storage_path.exists():
        return None
    return json.loads(storage_path.read_text())


def load_alarmo_bootstrap(path: str) -> dict[str, Any] | None:
    bootstrap_path = Path(path)
    if not bootstrap_path.exists():
        return None
    return json.loads(bootstrap_path.read_text())


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


def ensure_alarmo_config(
    base_url: str,
    token: str,
    *,
    code_disarm_required: bool,
    code_arm_required: bool,
    code_mode_change_required: bool,
    code_format: str,
    disarm_after_trigger: bool,
    ignore_blocking_sensors_after_trigger: bool,
) -> dict[str, Any]:
    storage = load_alarmo_storage()
    if storage is None:
        return {
            "changed": False,
            "reason": "alarmo_storage_missing",
        }

    current = storage["data"].get("config", {})
    desired = {
        "code_disarm_required": code_disarm_required,
        "code_arm_required": code_arm_required,
        "code_mode_change_required": code_mode_change_required,
        "code_format": code_format,
        "disarm_after_trigger": disarm_after_trigger,
        "ignore_blocking_sensors_after_trigger": ignore_blocking_sensors_after_trigger,
        "mqtt": current.get("mqtt", {}),
        "master": current.get("master", {}),
    }

    current_relevant = {
        key: current.get(key)
        for key in [
            "code_disarm_required",
            "code_arm_required",
            "code_mode_change_required",
            "code_format",
            "disarm_after_trigger",
            "ignore_blocking_sensors_after_trigger",
        ]
    }
    desired_relevant = {
        key: desired[key]
        for key in current_relevant
    }

    if current_relevant == desired_relevant:
        return {
            "changed": False,
            "config": desired_relevant,
        }

    api(
        base_url,
        token,
        "POST",
        "/api/alarmo/config",
        desired,
    )
    return {
        "changed": True,
        "config": desired_relevant,
    }


def ensure_alarmo_area_modes(
    base_url: str,
    token: str,
    *,
    area_name: str,
    armed_away_enabled: bool,
    armed_away_exit_time: int,
    armed_away_entry_time: int,
    armed_away_trigger_time: int,
    armed_home_enabled: bool,
) -> dict[str, Any]:
    storage = load_alarmo_storage()
    if storage is None:
        return {
            "changed": False,
            "reason": "alarmo_storage_missing",
        }

    areas = storage["data"].get("areas", [])
    area = next((item for item in areas if item.get("name") == area_name), None)
    if area is None and areas:
        area = areas[0]
    if area is None:
        fail("Alarmo storage has no areas to configure.")

    current_modes = area.get("modes", {})
    desired_modes = {
        "armed_away": {
            "enabled": armed_away_enabled,
            "exit_time": armed_away_exit_time if armed_away_enabled else None,
            "entry_time": armed_away_entry_time if armed_away_enabled else None,
            "trigger_time": armed_away_trigger_time if armed_away_enabled else None,
        },
        "armed_home": {
            "enabled": armed_home_enabled,
            "exit_time": None,
            "entry_time": None,
            "trigger_time": armed_away_trigger_time if armed_home_enabled else None,
        },
    }

    current_relevant = {
        "armed_away": current_modes.get("armed_away"),
        "armed_home": current_modes.get("armed_home"),
    }
    if current_relevant == desired_modes:
        return {
            "changed": False,
            "area_id": area["area_id"],
            "modes": desired_modes,
        }

    api(
        base_url,
        token,
        "POST",
        "/api/alarmo/area",
        {
            "area_id": area["area_id"],
            "modes": desired_modes,
        },
    )
    return {
        "changed": True,
        "area_id": area["area_id"],
        "modes": desired_modes,
    }


def ensure_alarmo_sensor(
    base_url: str,
    token: str,
    entity_id: str,
    sensor_type: str,
    area_name: str,
    modes: list[str],
) -> dict[str, Any]:
    storage = load_alarmo_storage()
    if storage is None:
        return {
            "created": False,
            "reason": "alarmo_storage_missing",
        }

    sensors = storage["data"].get("sensors", [])
    existing = next(
        (sensor for sensor in sensors if sensor.get("entity_id") == entity_id),
        None,
    )
    if existing is not None:
        return {
            "created": False,
            "entity_id": entity_id,
            "area": existing.get("area"),
            "modes": existing.get("modes", []),
        }

    areas = storage["data"].get("areas", [])
    area = next((item for item in areas if item.get("name") == area_name), None)
    if area is None and areas:
        area = areas[0]
    if area is None:
        fail("Alarmo storage has no areas to attach the bootstrap sensor to.")

    api(
        base_url,
        token,
        "POST",
        "/api/alarmo/sensors",
        {
            "entity_id": entity_id,
            "type": sensor_type,
            "modes": modes,
            "use_exit_delay": True,
            "use_entry_delay": True,
            "enabled": True,
            "area": area["area_id"],
        },
    )
    return {
        "created": True,
        "entity_id": entity_id,
        "area": area["area_id"],
        "modes": modes,
    }


def ensure_alarmo_user(
    base_url: str,
    token: str,
    *,
    name: str,
    code: str,
    can_arm: bool,
    can_disarm: bool,
) -> dict[str, Any]:
    storage = load_alarmo_storage()
    if storage is None:
        return {
            "changed": False,
            "reason": "alarmo_storage_missing",
        }

    users = storage["data"].get("users", [])
    existing = next((user for user in users if user.get("name") == name), None)
    desired = {
        "name": name,
        "code": code,
        "enabled": True,
        "can_arm": can_arm,
        "can_disarm": can_disarm,
        "is_override_code": False,
        "area_limit": [],
    }

    current_relevant = None
    if existing is not None:
        current_relevant = {
            "name": existing.get("name"),
            "code": existing.get("code"),
            "enabled": existing.get("enabled", True),
            "can_arm": existing.get("can_arm", False),
            "can_disarm": existing.get("can_disarm", False),
            "is_override_code": existing.get("is_override_code", False),
            "area_limit": existing.get("area_limit", []),
        }

    if current_relevant == desired:
        return {
            "changed": False,
            "user_id": existing.get("user_id"),
            "name": name,
        }

    payload = dict(desired)
    if existing is not None:
        payload["user_id"] = existing["user_id"]

    result = api(
        base_url,
        token,
        "POST",
        "/api/alarmo/users",
        payload,
    )
    if not result.get("success", False):
        fail(f"Alarmo user update failed: {result.get('error') or result}")

    return {
        "changed": True,
        "user_id": payload.get("user_id"),
        "name": name,
    }


def set_input_text_value(
    base_url: str,
    token: str,
    entity_id: str,
    value: str,
) -> dict[str, Any]:
    api(
        base_url,
        token,
        "POST",
        "/api/services/input_text/set_value",
        {
            "entity_id": entity_id,
            "value": value,
        },
    )
    return {
        "entity_id": entity_id,
        "value": value,
    }


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
            "Ensure Home Assistant MQTT, Frigate, and Alarmo are bootstrapped, "
            "prefer the Frigate high-quality live stream, and seed mobile notifications."
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
    parser.add_argument("--default-notify-service", default="")
    parser.add_argument(
        "--alarmo-sensor-entity",
        default="binary_sensor.studio_person_occupancy",
    )
    parser.add_argument("--alarmo-sensor-type", default="motion")
    parser.add_argument("--alarmo-area-name", default="Alarmo")
    parser.add_argument(
        "--alarmo-bootstrap-file",
        default="/config/alarmo-bootstrap.json",
    )
    parser.add_argument("--alarmo-away-exit-time", type=int, default=30)
    parser.add_argument("--alarmo-away-entry-time", type=int, default=20)
    parser.add_argument("--alarmo-trigger-time", type=int, default=180)
    parser.add_argument("--alarmo-enable-armed-home", action="store_true")
    parser.add_argument("--skip-mqtt", action="store_true")
    parser.add_argument("--skip-alarmo", action="store_true")
    parser.add_argument("--skip-alarmo-sensor", action="store_true")
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
        "alarmo_config": None,
        "alarmo_area": None,
        "alarmo_sensor": None,
        "alarmo_user": None,
        "notify_helper": None,
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

    alarmo_bootstrap = load_alarmo_bootstrap(args.alarmo_bootstrap_file)

    summary["frigate_options"] = sync_frigate_options(
        args.base_url,
        token,
        frigate_entry,
        args.rtsp_url_template,
    )

    if args.default_notify_service:
        summary["notify_helper"] = set_input_text_value(
            args.base_url,
            token,
            "input_text.frigate_notify_action",
            args.default_notify_service,
        )
    else:
        summary["notify_helper"] = {
            "skipped": True,
        }

    if args.skip_alarmo:
        summary["alarmo_config"] = {
            "skipped": True,
        }
        summary["alarmo_area"] = {
            "skipped": True,
        }
        summary["alarmo_user"] = {
            "skipped": True,
        }
    else:
        code_value = (
            alarmo_bootstrap.get("user_code", "") if alarmo_bootstrap is not None else ""
        )
        code_format = "number" if code_value.isdigit() else "text"
        summary["alarmo_config"] = ensure_alarmo_config(
            args.base_url,
            token,
            code_disarm_required=bool(code_value),
            code_arm_required=False,
            code_mode_change_required=False,
            code_format=code_format,
            disarm_after_trigger=False,
            ignore_blocking_sensors_after_trigger=False,
        )
        summary["alarmo_area"] = ensure_alarmo_area_modes(
            args.base_url,
            token,
            area_name=args.alarmo_area_name,
            armed_away_enabled=True,
            armed_away_exit_time=args.alarmo_away_exit_time,
            armed_away_entry_time=args.alarmo_away_entry_time,
            armed_away_trigger_time=args.alarmo_trigger_time,
            armed_home_enabled=args.alarmo_enable_armed_home,
        )
        if alarmo_bootstrap is None:
            summary["alarmo_user"] = {
                "skipped": True,
                "reason": "bootstrap_file_missing",
            }
        elif not alarmo_bootstrap.get("user_name") or not code_value:
            summary["alarmo_user"] = {
                "skipped": True,
                "reason": "bootstrap_values_missing",
            }
        else:
            summary["alarmo_user"] = ensure_alarmo_user(
                args.base_url,
                token,
                name=alarmo_bootstrap["user_name"],
                code=code_value,
                can_arm=True,
                can_disarm=True,
            )

    if args.skip_alarmo or args.skip_alarmo_sensor:
        summary["alarmo_sensor"] = {
            "skipped": True,
        }
    else:
        summary["alarmo_sensor"] = ensure_alarmo_sensor(
            args.base_url,
            token,
            args.alarmo_sensor_entity,
            args.alarmo_sensor_type,
            args.alarmo_area_name,
            ["armed_away"],
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
        "--default-notify-service",
        args.default_notify_service,
        "--alarmo-sensor-entity",
        args.alarmo_sensor_entity,
        "--alarmo-sensor-type",
        args.alarmo_sensor_type,
        "--alarmo-area-name",
        args.alarmo_area_name,
        "--alarmo-bootstrap-file",
        args.alarmo_bootstrap_file,
        "--alarmo-away-exit-time",
        str(args.alarmo_away_exit_time),
        "--alarmo-away-entry-time",
        str(args.alarmo_away_entry_time),
        "--alarmo-trigger-time",
        str(args.alarmo_trigger_time),
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
    if args.skip_alarmo_sensor:
        remote_command.append("--skip-alarmo-sensor")
    if args.alarmo_enable_armed_home:
        remote_command.append("--alarmo-enable-armed-home")
    command = ssh_prefix(args.deploy_user, args.deploy_host, args.ssh_option)
    command.append(shlex.join(remote_command))
    return command


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sync Home Assistant's MQTT, Frigate, and Alarmo integrations "
            "so HA uses the high-quality Frigate main stream and has a usable security baseline."
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
    parser.add_argument("--default-notify-service", default="notify.mobile_app_youphone")
    parser.add_argument(
        "--alarmo-sensor-entity",
        default="binary_sensor.studio_person_occupancy",
    )
    parser.add_argument("--alarmo-sensor-type", default="motion")
    parser.add_argument("--alarmo-area-name", default="Alarmo")
    parser.add_argument("--alarmo-bootstrap-file", default="/config/alarmo-bootstrap.json")
    parser.add_argument("--alarmo-away-exit-time", type=int, default=30)
    parser.add_argument("--alarmo-away-entry-time", type=int, default=20)
    parser.add_argument("--alarmo-trigger-time", type=int, default=180)
    parser.add_argument("--alarmo-enable-armed-home", action="store_true")
    parser.add_argument("--skip-mqtt", action="store_true")
    parser.add_argument("--skip-alarmo", action="store_true")
    parser.add_argument("--skip-alarmo-sensor", action="store_true")
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
