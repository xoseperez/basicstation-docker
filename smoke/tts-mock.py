#!/usr/bin/env python3
"""HTTPS stand-in for the parts of The Things Stack API that autoprovisioning
uses. smoke-test.sh runs it as a sidecar; it needs only the standard library.

Every request is appended to /records/requests.jsonl (method, path, headers
and parsed body), so the test can check exactly what the gateway sent. The
reply depends on the first word in /records/mode, read on every request:

  ok        the gateway is registered and a key is issued
  exists    registering answers "already registered" (code 6), a key is issued
  nokey     the key request answers {}
  emptykey  the key request answers {"key": ""}

Usage: tts-mock.py CERT KEY
"""

import http.server
import json
import re
import ssl
import sys

RECORDS = "/records/requests.jsonl"
MODE_FILE = "/records/mode"
API_KEY = "NNSXS.SMOKETEST.MOCKKEY"
API_KEY_NAME = "autoprovision-lns-key"


def mode():
    try:
        with open(MODE_FILE) as f:
            return (f.read().split() or ["ok"])[0]
    except OSError:
        return "ok"


class Handler(http.server.BaseHTTPRequestHandler):

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_request(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else None
        except ValueError:
            body = {"invalid_json": raw.decode(errors="replace")}
        with open(RECORDS, "a") as f:
            f.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "headers": dict(self.headers),
                "body": body,
            }) + "\n")

        current = mode()
        if self.command == "POST" and re.fullmatch(r"/api/v3/users/[^/]+/gateways", self.path):
            if current == "exists":
                return self.reply(409, {"code": 6, "message": "gateway already registered"})
            return self.reply(200, (body or {}).get("gateway", {}))

        keys = re.fullmatch(r"/api/v3/gateways/[^/]+/api-keys(?:/([^/]+))?", self.path)
        if keys and self.command == "GET" and keys.group(1) is None:
            return self.reply(200, {"api_keys": [
                {"id": "OLDKEY", "name": API_KEY_NAME},
                {"id": "OTHERKEY", "name": "a-key-someone-else-made"},
            ]})
        if keys and self.command == "PUT" and keys.group(1):
            return self.reply(200, {"id": keys.group(1)})
        if keys and self.command == "POST" and keys.group(1) is None:
            if current == "nokey":
                return self.reply(200, {})
            if current == "emptykey":
                return self.reply(200, {"key": ""})
            return self.reply(200, {"id": "NEWKEY", "key": API_KEY})

        self.reply(404, {"code": 5, "message": "not found"})

    do_GET = do_POST = do_PUT = handle_request

    def log_message(self, fmt, *args):
        sys.stderr.write("tts-mock: " + (fmt % args) + "\n")


def main():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(sys.argv[1], sys.argv[2])
    server = http.server.ThreadingHTTPServer(("", 443), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print("tts-mock listening on 443", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
