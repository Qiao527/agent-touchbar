#!/usr/bin/env python3
"""Exercise the real atb executable against an isolated local HTTP fixture."""

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


ATB = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else None
if ATB is None or not ATB.is_file():
    raise SystemExit("Usage: python3 scripts/smoke-test.py /path/to/atb")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer smoke-test-token":
            return self.respond({}, 401)
        self.respond({"ok": True})

    def do_POST(self):
        if self.headers.get("Authorization") != "Bearer smoke-test-token":
            return self.respond({}, 401)
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.received.append((self.path, body))
        self.respond({"decision": self.server.decision} if self.path == "/v1/permission" else {"ok": True})


class CLITests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="atb-smoke-")
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.received = []
        self.server.decision = "allow"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        (self.config / "config.yaml").write_text(f"server: {{port: {self.server.server_port}}}\n")
        (self.config / "token").write_text("smoke-test-token")
        self.environment = dict(os.environ, AGENT_TOUCHBAR_HOME=str(self.config), AGENT_TOUCHBAR_LANG="en")

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def run_cli(self, *args, data="", binary=ATB):
        return subprocess.run([str(binary), *args], input=data, text=True, capture_output=True,
                              timeout=10, env=self.environment)

    def test_help_and_status(self):
        self.assertIn("Usage:", self.run_cli("--help").stdout)
        result = self.run_cli("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("is running", result.stdout)

    def test_notification_payload(self):
        result = self.run_cli("notify", "--title", "Build finished", "--detail", "All tests passed", "--ttl", "20")
        self.assertEqual(result.returncode, 0, result.stderr)
        path, body = self.server.received[-1]
        self.assertEqual(path, "/v1/notify")
        self.assertEqual(body["title"], "Build finished")
        self.assertEqual(body["ttl"], 20)

    def test_hook_events(self):
        for agent in ("claude", "codex"):
            result = self.run_cli("hook", agent, data=json.dumps({"hook_event_name": "Stop", "session_id": "smoke"}))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            path, body = self.server.received[-1]
            self.assertEqual((path, body["agent"], body["state"]), ("/v1/agent", agent, "done"))

    def test_permission_decisions(self):
        for agent in ("claude", "codex"):
            for decision in ("allow", "deny", "none"):
                self.server.decision = decision
                result = self.run_cli("hook", agent, data=json.dumps({
                    "hook_event_name": "PermissionRequest", "session_id": "smoke",
                    "tool_name": "Bash", "tool_input": {"command": "swift test"}}))
                self.assertEqual(result.returncode, 0, result.stderr)
                if decision == "none":
                    self.assertEqual(result.stdout, "")
                else:
                    output = json.loads(result.stdout)["hookSpecificOutput"]
                    self.assertEqual(output["decision"]["behavior"], decision)

    def test_authentication_failure_and_malformed_input(self):
        (self.config / "token").write_text("wrong-token")
        self.assertNotEqual(self.run_cli("status").returncode, 0)
        self.assertNotEqual(self.run_cli("notify", "--title", "Test").returncode, 0)
        for payload in ("bad json", '{"hook_event_name":"Stop"}'):
            result = self.run_cli("hook", "claude", data=payload)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_missing_app_falls_back_without_a_decision(self):
        # Close a reserved socket so the configured port has no listener.
        import socket
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]
        (self.config / "config.yaml").write_text(f"server: {{port: {port}}}\n")
        for event in ("Stop", "PermissionRequest"):
            result = self.run_cli("hook", "claude", data=json.dumps({"hook_event_name": event}))
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_init_preserves_existing_configuration(self):
        original = (self.config / "config.yaml").read_bytes()
        self.assertEqual(self.run_cli("init").returncode, 0)
        self.assertEqual((self.config / "config.yaml").read_bytes(), original)
        (self.config / "config.yaml").unlink()
        self.assertEqual(self.run_cli("init").returncode, 0)
        self.assertIn("version: 1", (self.config / "config.yaml").read_text())

    def test_invalid_notification_options_fail_before_sending(self):
        for args in (("--ttl", "nan"), ("--ttl", "-1"), ("--priority", "invalid"), ("--unknown", "value")):
            result = self.run_cli("notify", "--title", "Test", *args)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.server.received, [])

    def test_generated_hooks_escape_installation_paths(self):
        binary = self.config / 'a space, apostrophe\' and "quote"' / "atb"
        binary.parent.mkdir()
        shutil.copy2(ATB, binary)
        result = self.run_cli("hooks", "claude", binary=binary)
        self.assertEqual(result.returncode, 0, result.stderr)
        hooks = json.loads(result.stdout.split("\n", 1)[1])["hooks"]
        command = hooks["PermissionRequest"][0]["hooks"][0]["command"]
        self.assertEqual(shlex.split(command), [str(binary), "hook", "claude"])
        codex = self.run_cli("hooks", "codex", binary=binary)
        # The generated TOML command uses JSON-compatible basic string escaping.
        commands = [line.split(" = ", 1)[1] for line in codex.stdout.splitlines() if line.startswith("command = ")]
        self.assertEqual(len(commands), 5)
        for encoded in commands:
            self.assertEqual(shlex.split(json.loads(encoded)), [str(binary), "hook", "codex"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
