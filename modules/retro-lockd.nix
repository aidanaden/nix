{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.homelab.retroLockd;

  lockdScript = pkgs.writeText "retro-lockd.py" ''
    import fcntl
    import json
    import os
    import time
    import uuid
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import parse_qs, urlparse

    HOST = "${cfg.listenAddress}"
    PORT = ${toString cfg.port}
    STATE_DIR = "${cfg.stateDir}"
    STATE_FILE = os.path.join(STATE_DIR, "state.json")
    DEFAULT_TTL = ${toString cfg.defaultTtlSeconds}


    def ensure_state_file():
        os.makedirs(STATE_DIR, exist_ok=True)
        if not os.path.exists(STATE_FILE):
            with open(STATE_FILE, "w", encoding="utf-8") as handle:
                json.dump({"leases": {}}, handle)


    def with_state(mutator):
        ensure_state_file()
        with open(STATE_FILE, "r+", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            try:
                try:
                    state = json.load(handle)
                except json.JSONDecodeError:
                    state = {"leases": {}}

                now = int(time.time())
                leases = state.setdefault("leases", {})
                expired = [
                    key for key, lease in leases.items() if lease.get("expiresAt", 0) <= now
                ]
                for key in expired:
                    leases.pop(key, None)

                result = mutator(state, now)
                handle.seek(0)
                handle.truncate()
                json.dump(state, handle, sort_keys=True)
                handle.flush()
                os.fsync(handle.fileno())
                return result
            finally:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


    def lease_key(payload):
        game_id = str(payload.get("gameId", "")).strip()
        runtime_profile = str(payload.get("runtimeProfile", "")).strip()
        if not game_id or not runtime_profile:
            return None
        return f"{game_id}::{runtime_profile}"


    class Handler(BaseHTTPRequestHandler):
        server_version = "retro-lockd/0.1"

        def log_message(self, format_string, *args):
            return

        def read_json(self):
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b"{}"
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))

        def send_json(self, status, payload):
            body = json.dumps(payload, sort_keys=True).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/health"):
                self.send_json(200, {"ok": True})
                return

            if self.path.startswith("/lease/status"):
                payload = {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()}
                key = lease_key(payload)
                if key is None:
                    self.send_json(400, {"error": "gameId and runtimeProfile are required"})
                    return

                def status(state, now):
                    lease = state["leases"].get(key)
                    return {
                        "held": lease is not None,
                        "key": key,
                        "lease": lease,
                        "now": now,
                        "ok": True,
                    }

                self.send_json(200, with_state(status))
                return

            self.send_json(404, {"error": "not found"})

        def do_POST(self):
            if self.path not in (
                "/lease/acquire",
                "/lease/renew",
                "/lease/release",
            ):
                self.send_json(404, {"error": "not found"})
                return

            try:
                payload = self.read_json()
            except json.JSONDecodeError:
                self.send_json(400, {"error": "invalid json"})
                return

            if self.path == "/lease/acquire":
                key = lease_key(payload)
                if key is None:
                    self.send_json(400, {"error": "gameId and runtimeProfile are required"})
                    return

                host = str(payload.get("host", "unknown")).strip() or "unknown"
                ttl = int(payload.get("ttlSeconds") or DEFAULT_TTL)
                ttl = ttl if ttl > 0 else DEFAULT_TTL

                def acquire(state, now):
                    existing = state["leases"].get(key)
                    if existing and existing["expiresAt"] > now and existing["host"] != host:
                        return {"granted": False, "key": key, "lease": existing, "ok": True}

                    lease_id = (
                        existing.get("leaseId")
                        if existing and existing.get("host") == host
                        else str(uuid.uuid4())
                    )
                    lease = {
                        "expiresAt": now + ttl,
                        "gameId": str(payload.get("gameId", "")).strip(),
                        "grantedAt": now,
                        "host": host,
                        "leaseId": lease_id,
                        "runtimeProfile": str(payload.get("runtimeProfile", "")).strip(),
                    }
                    state["leases"][key] = lease
                    return {"granted": True, "key": key, "lease": lease, "ok": True}

                self.send_json(200, with_state(acquire))
                return

            lease_id = str(payload.get("leaseId", "")).strip()
            if not lease_id:
                self.send_json(400, {"error": "leaseId is required"})
                return

            ttl = int(payload.get("ttlSeconds") or DEFAULT_TTL)
            ttl = ttl if ttl > 0 else DEFAULT_TTL

            if self.path == "/lease/renew":
                def renew(state, now):
                    for key, lease in state["leases"].items():
                        if lease.get("leaseId") == lease_id:
                            lease["expiresAt"] = now + ttl
                            return {
                                "key": key,
                                "lease": lease,
                                "ok": True,
                                "renewed": True,
                            }
                    return {"lease": None, "ok": True, "renewed": False}

                self.send_json(200, with_state(renew))
                return

            def release(state, now):
                for key, lease in list(state["leases"].items()):
                    if lease.get("leaseId") == lease_id:
                        state["leases"].pop(key, None)
                        return {
                            "key": key,
                            "lease": lease,
                            "ok": True,
                            "released": True,
                        }
                return {"lease": None, "ok": True, "released": False}

            self.send_json(200, with_state(release))


    def main():
        ensure_state_file()
        server = ThreadingHTTPServer((HOST, PORT), Handler)
        server.serve_forever()


    if __name__ == "__main__":
        main()
  '';
in {
  options.homelab.retroLockd = {
    enable = lib.mkEnableOption "retro writer lease coordinator";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "retro-lockd listen address.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5110;
      description = "retro-lockd listen port.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/retro/lockd";
      description = "retro-lockd state directory.";
    };

    defaultTtlSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "Default lease TTL in seconds.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 aidan users -"
    ];

    systemd.services.retro-lockd = {
      description = "Retro single-writer lease coordinator";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "tailscaled.service"];
      wants = ["network-online.target"];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python ${lockdScript}";
        Group = "users";
        Restart = "on-failure";
        RestartSec = 3;
        User = "aidan";
        WorkingDirectory = cfg.stateDir;
      };
    };
  };
}
