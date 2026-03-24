#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: rotate-amcrest-rtsp-password.sh [options]

Rotate the configured Amcrest RTSP user's password without putting it in shell
history or chat logs. By default this:
1. prompts for a new password
2. waits for you to change that password in the camera UI
3. updates secrets/secrets.yaml via sops

Optional flags can also update the camera directly over the Amcrest HTTP API and
deploy aidan-mini from a clean temporary jj workspace.

Options:
  --update-camera              Rotate the camera-side password via Amcrest CGI.
  --deploy                     Deploy aidan-mini after updating the secret.
  --camera-host HOST           Camera host. Default: 192.168.1.5
  --camera-port PORT           Camera HTTP port. Default: 80
  --camera-scheme SCHEME       Camera scheme. Default: http
  --camera-auth-user USER      Auth user for --update-camera. Default: current RTSP user
  --deploy-host HOST           SSH host for deployment. Default: aidan-mini
  --deploy-user USER           SSH user for deployment. Default: aidan
  --deploy-system HOSTNAME     Flake host name to rebuild. Default: aidan-mini
  --deploy-revision REV        jj revision to deploy from. Default: main
  --secrets-file PATH          Secrets file path. Default: secrets/secrets.yaml
  --help                       Show this help

Examples:
  scripts/rotate-amcrest-rtsp-password.sh
  scripts/rotate-amcrest-rtsp-password.sh --update-camera --deploy
  scripts/rotate-amcrest-rtsp-password.sh --deploy-host 100.82.7.106 --deploy
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$cmd" >&2
    exit 1
  fi
}

prompt_secret() {
  local prompt="$1"
  local first=""
  local second=""

  read -r -s "?${prompt}" first
  printf '\n'
  read -r -s '?Confirm password: ' second
  printf '\n'

  if [[ -z "$first" ]]; then
    printf 'Password cannot be empty.\n' >&2
    exit 1
  fi

  if [[ "$first" != "$second" ]]; then
    printf 'Passwords did not match.\n' >&2
    exit 1
  fi

  printf '%s' "$first"
}

read_secret_value() {
  local key="$1"
  sops decrypt --extract "[\"${key}\"]" "$secrets_file"
}

update_sops_secret() {
  local tmp_json
  local tmp_yaml

  tmp_json="$(mktemp /tmp/amcrest-rotate.XXXXXX.json)"
  tmp_yaml="$(mktemp /tmp/amcrest-rotate.XXXXXX.yaml)"

  cleanup_files+=("$tmp_json" "$tmp_yaml")

  sops decrypt --input-type yaml --output-type json "$secrets_file" >"$tmp_json"

  python3 - "$tmp_json" "$rtsp_user" "$new_password" <<'PY'
import json
import sys

path, user, password = sys.argv[1:]

with open(path, "r", encoding="utf-8") as infile:
    data = json.load(infile)

data["amcrest_rtsp_user"] = user
data["amcrest_rtsp_password"] = password

with open(path, "w", encoding="utf-8") as outfile:
    json.dump(data, outfile, indent=2, sort_keys=True)
    outfile.write("\n")
PY

  sops encrypt \
    --input-type json \
    --output-type yaml \
    --filename-override "$secrets_file" \
    --output "$tmp_yaml" \
    "$tmp_json"

  mv "$tmp_yaml" "$secrets_file"
}

rotate_camera_password() {
  local auth_user="$camera_auth_user"
  local auth_password="$current_password"
  local response=""

  if [[ -z "$auth_user" ]]; then
    auth_user="$rtsp_user"
  fi

  if [[ "$auth_user" != "$rtsp_user" ]]; then
    read -r -s "?Password for camera auth user ${auth_user}: " auth_password
    printf '\n'
  fi

  response="$(
    curl --digest --silent --show-error --fail \
      --user "${auth_user}:${auth_password}" \
      --get "${camera_scheme}://${camera_host}:${camera_port}/cgi-bin/userManager.cgi" \
      --data-urlencode "action=modifyPassword" \
      --data-urlencode "name=${rtsp_user}" \
      --data-urlencode "pwd=${new_password}" \
      --data-urlencode "pwdOld=${current_password}"
  )"

  if [[ "$response" != "OK" ]]; then
    printf 'Camera password update did not return OK: %s\n' "$response" >&2
    exit 1
  fi
}

deploy_aidan_mini() {
  local workspace_name
  local workspace_dir
  local remote_dir

  workspace_name="rotate-amcrest-$$"
  workspace_dir="$(mktemp -d /tmp/rotate-amcrest-workspace.XXXXXX)"
  remote_dir="/home/${deploy_user}/$(basename "$workspace_dir")"

  cleanup_dirs+=("$workspace_dir")
  cleanup_workspace="$workspace_name"
  cleanup_remote_dir="$remote_dir"

  jj workspace add --name "$workspace_name" -r "$deploy_revision" "$workspace_dir" >/dev/null
  cp "$secrets_file" "$workspace_dir/secrets/secrets.yaml"

  (
    cd "$workspace_dir"
    nix eval --raw ".#nixosConfigurations.${deploy_system}.config.system.build.toplevel.drvPath" \
      >/dev/null
  )

  ssh "${deploy_user}@${deploy_host}" "rm -rf '${remote_dir}'"
  scp -O -r "$workspace_dir" "${deploy_user}@${deploy_host}:/home/${deploy_user}/"

  ssh "${deploy_user}@${deploy_host}" \
    "cd '${remote_dir}' && sudo nixos-rebuild switch --flake '.#${deploy_system}'"

  ssh "${deploy_user}@${deploy_host}" \
    "sudo docker exec -i frigate python3 - <<'PY'
import json
import urllib.request

with urllib.request.urlopen('http://127.0.0.1:1984/api/streams', timeout=5) as resp:
    data = json.load(resp)

for name in ('studio_main', 'studio_sub'):
    entry = data.get(name, {})
    if not entry.get('producers'):
        raise SystemExit(f'{name}: no live producer after deploy')

print('Frigate streams are live.')
PY"
}

cleanup() {
  local path

  for path in "${cleanup_files[@]}"; do
    [[ -e "$path" ]] && rm -f "$path"
  done

  for path in "${cleanup_dirs[@]}"; do
    [[ -e "$path" ]] && rm -rf "$path"
  done

  if [[ -n "${cleanup_remote_dir:-}" ]]; then
    ssh "${deploy_user}@${deploy_host}" "rm -rf '${cleanup_remote_dir}'" >/dev/null 2>&1 || true
  fi

  if [[ -n "${cleanup_workspace:-}" ]]; then
    jj workspace forget "$cleanup_workspace" >/dev/null 2>&1 || true
  fi
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

update_camera=0
deploy=0
camera_host="192.168.1.5"
camera_port="80"
camera_scheme="http"
camera_auth_user=""
deploy_host="aidan-mini"
deploy_user="aidan"
deploy_system="aidan-mini"
deploy_revision="main"
secrets_file="secrets/secrets.yaml"

cleanup_files=()
cleanup_dirs=()
cleanup_workspace=""
cleanup_remote_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-camera)
      update_camera=1
      shift
      ;;
    --deploy)
      deploy=1
      shift
      ;;
    --camera-host)
      camera_host="$2"
      shift 2
      ;;
    --camera-port)
      camera_port="$2"
      shift 2
      ;;
    --camera-scheme)
      camera_scheme="$2"
      shift 2
      ;;
    --camera-auth-user)
      camera_auth_user="$2"
      shift 2
      ;;
    --deploy-host)
      deploy_host="$2"
      shift 2
      ;;
    --deploy-user)
      deploy_user="$2"
      shift 2
      ;;
    --deploy-system)
      deploy_system="$2"
      shift 2
      ;;
    --deploy-revision)
      deploy_revision="$2"
      shift 2
      ;;
    --secrets-file)
      secrets_file="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

trap cleanup EXIT

require_cmd curl
require_cmd jj
require_cmd nix
require_cmd python3
require_cmd scp
require_cmd sops
require_cmd ssh

if [[ ! -f "$secrets_file" ]]; then
  printf 'Secrets file not found: %s\n' "$secrets_file" >&2
  exit 1
fi

rtsp_user="$(read_secret_value amcrest_rtsp_user)"
current_password="$(read_secret_value amcrest_rtsp_password)"
new_password="$(prompt_secret "New password for camera user ${rtsp_user}: ")"

if [[ "$new_password" == "$current_password" ]]; then
  printf 'New password matches the current stored password. Nothing to do.\n' >&2
  exit 1
fi

if (( update_camera )); then
  rotate_camera_password
  printf 'Camera password updated over API for user %s.\n' "$rtsp_user"
else
  printf 'Change the %s password in the camera UI now, then press Enter to continue.' "$rtsp_user"
  read -r _
fi

update_sops_secret
printf 'Updated %s in %s.\n' "amcrest_rtsp_password" "$secrets_file"

if (( deploy )); then
  deploy_aidan_mini
  printf 'Deployed %s from revision %s.\n' "$deploy_system" "$deploy_revision"
else
  printf 'Local secret updated. Redeploy %s when ready.\n' "$deploy_system"
fi
