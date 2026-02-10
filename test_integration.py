#!/usr/bin/env python3
"""Integration test for the Vector HTTP forward sink.

Starts a catch-all HTTP server, runs Vector with vector_local.yaml,
sends a test JSON payload, and verifies the forwarded request has
correct body structure, auth headers, and custom headers.

Usage:
    python3 test_integration.py

Requires: `vector` binary on PATH.
"""

import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request

VECTOR_ADDR = "127.0.0.1"
VECTOR_PORT = 8080
VECTOR_API_PORT = 8686
CATCH_ALL_PORT = 9090

TEST_TOKEN = "test-token"
TEST_WORKSPACE_URL = "https://test-workspace.databricks.com"
TEST_TABLE_NAME = "catalog.schema.test_table"

TEST_PAYLOAD = {"event": "test", "number": 42, "nested": {"a": 1}}

FORWARD_TIMEOUT_SECS = 10


class CatchAllHandler(http.server.BaseHTTPRequestHandler):
    """Records incoming requests for later assertion."""

    requests = []
    event = threading.Event()

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)
        self.requests.append({
            "headers": dict(self.headers),
            "body": body,
            "path": self.path,
        })
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
        self.event.set()

    def log_message(self, format, *args):
        # Suppress default access log noise
        pass


def check_port_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("127.0.0.1", port)) != 0


def wait_for_health(url, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=2) as resp:
                if resp.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


def main():
    # --- Preflight checks ---
    if not shutil.which("vector"):
        print("FAIL: 'vector' binary not found on PATH")
        return 1

    for port in (VECTOR_PORT, CATCH_ALL_PORT):
        if not check_port_free(port):
            print(f"FAIL: Port {port} is already in use")
            return 1

    # --- Start catch-all HTTP server ---
    CatchAllHandler.requests.clear()
    CatchAllHandler.event.clear()
    server = http.server.HTTPServer(("127.0.0.1", CATCH_ALL_PORT), CatchAllHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"[setup] Catch-all server listening on 127.0.0.1:{CATCH_ALL_PORT}")

    # --- Start Vector ---
    env = os.environ.copy()
    env["FORWARD_URL"] = f"http://127.0.0.1:{CATCH_ALL_PORT}"
    env["FORWARD_AUTH_TOKEN"] = TEST_TOKEN
    env["DATABRICKS_WORKSPACE_URL"] = TEST_WORKSPACE_URL
    env["DATABRICKS_TABLE_NAME"] = TEST_TABLE_NAME

    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vector_local.yaml")
    vector_proc = subprocess.Popen(
        ["vector", "--config", config_path],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print("[setup] Vector starting...")

    try:
        # --- Wait for Vector health ---
        health_url = f"http://127.0.0.1:{VECTOR_API_PORT}/health"
        if not wait_for_health(health_url):
            print("FAIL: Vector did not become healthy within timeout")
            stderr = vector_proc.stderr.read().decode(errors="replace")
            if stderr:
                print(f"[vector stderr]\n{stderr}")
            return 1
        print("[setup] Vector is healthy")

        # --- Send test payload ---
        payload_bytes = json.dumps(TEST_PAYLOAD).encode()
        req = urllib.request.Request(
            f"http://127.0.0.1:{VECTOR_PORT}",
            data=payload_bytes,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status != 200:
                print(f"FAIL: Vector returned status {resp.status}")
                return 1
        print("[test] Payload sent to Vector")

        # --- Wait for forwarded request ---
        if not CatchAllHandler.event.wait(timeout=FORWARD_TIMEOUT_SECS):
            print(f"FAIL: No forwarded request received within {FORWARD_TIMEOUT_SECS}s")
            stderr = vector_proc.stderr.read().decode(errors="replace")
            if stderr:
                print(f"[vector stderr]\n{stderr}")
            return 1

        # Give a brief moment for any additional requests
        time.sleep(0.5)

        if not CatchAllHandler.requests:
            print("FAIL: No requests recorded by catch-all server")
            return 1

        forwarded = CatchAllHandler.requests[0]
        headers = forwarded["headers"]
        raw_body = json.loads(forwarded["body"])

        # Vector may batch events into a JSON array
        if isinstance(raw_body, list):
            if len(raw_body) == 0:
                print("FAIL: Forwarded body is an empty array")
                return 1
            body = raw_body[0]
        else:
            body = raw_body

        failures = []

        # --- Assert body structure ---
        if "message" not in body:
            failures.append("Body missing 'message' field")
        else:
            msg = body["message"]
            for key in TEST_PAYLOAD:
                if key not in msg:
                    failures.append(f"Body 'message' missing key '{key}'")
                elif msg[key] != TEST_PAYLOAD[key]:
                    failures.append(f"Body 'message.{key}': expected {TEST_PAYLOAD[key]!r}, got {msg[key]!r}")

        if "request_metadata" not in body:
            failures.append("Body missing 'request_metadata' field")

        # --- Assert headers ---
        auth = headers.get("authorization") or headers.get("Authorization")
        if auth != f"Bearer {TEST_TOKEN}":
            failures.append(f"Authorization: expected 'Bearer {TEST_TOKEN}', got {auth!r}")

        ct = headers.get("content-type") or headers.get("Content-Type")
        if ct and "application/json" not in ct:
            failures.append(f"Content-Type: expected 'application/json', got {ct!r}")

        uce = headers.get("unity-catalog-endpoint")
        if uce != TEST_WORKSPACE_URL:
            failures.append(f"unity-catalog-endpoint: expected {TEST_WORKSPACE_URL!r}, got {uce!r}")

        dtn = headers.get("x-databricks-zerobus-table-name")
        if dtn != TEST_TABLE_NAME:
            failures.append(f"x-databricks-zerobus-table-name: expected {TEST_TABLE_NAME!r}, got {dtn!r}")

        # --- Report results ---
        if failures:
            print("\nFAIL:")
            for f in failures:
                print(f"  - {f}")
            print(f"\n[debug] Forwarded body:\n{json.dumps(body, indent=2)}")
            print(f"[debug] Forwarded headers:\n{json.dumps(dict(headers), indent=2)}")
            return 1

        print("\nPASS: All assertions passed")
        print(f"  - Body has 'message' with original payload")
        print(f"  - Body has 'request_metadata'")
        print(f"  - Authorization: Bearer {TEST_TOKEN}")
        print(f"  - Content-Type: application/json")
        print(f"  - unity-catalog-endpoint: {TEST_WORKSPACE_URL}")
        print(f"  - x-databricks-zerobus-table-name: {TEST_TABLE_NAME}")
        return 0

    finally:
        # --- Cleanup ---
        vector_proc.terminate()
        try:
            vector_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            vector_proc.kill()
        server.shutdown()
        print("[cleanup] Vector and catch-all server stopped")


if __name__ == "__main__":
    sys.exit(main())
