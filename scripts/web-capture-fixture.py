#!/usr/bin/env python3
"""Loopback-only WebKit fixture proxy. Never resolve or forward a destination."""

import argparse
import json
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
from pathlib import Path
from threading import Event, Lock
from urllib.parse import urlsplit


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self):
        # HTTPServer performs reverse DNS even for numeric loopback. This fixture
        # has a fixed local identity and must not depend on a resolver.
        TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.events = []
        self.lock = Lock()
        self.holds = {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            pass  # WebKit deliberately closes connections on cancellation.

    def log_message(self, _format, *args):
        pass

    def do_CONNECT(self):
        # HTTP CONNECT terminates here. The next plaintext HTTP request on this
        # connection is handled locally, never tunneled to the named authority.
        self.send_response(200)
        self.end_headers()
        self.close_connection = False

    def do_GET(self):
        parsed = urlsplit(self.path)
        path = parsed.path
        host = parsed.netloc or self.headers.get("Host", "")
        if path == "/ledger":
            with self.server.lock:
                body = json.dumps(self.server.events).encode()
            self.reply(body, "application/json")
            return
        route, _, key = path.lstrip("/").partition("/")
        event = {"host": host, "path": path}
        if route == "sso-private":
            # Keep only a boolean in the receipt, never a Cookie header.
            cookies = SimpleCookie()
            cookies.load(self.headers.get("Cookie", ""))
            session = cookies.get("vitrine_session")
            event["sessionSeen"] = str(session is not None and session.value == key).lower()
        with self.server.lock:
            self.server.events.append(event)
        if route == "release":
            with self.server.lock:
                event = self.server.holds.setdefault(key, Event())
            event.set()
            self.reply(b"released", "text/plain")
            return
        if route == "hold":
            with self.server.lock:
                event = self.server.holds.setdefault(key, Event())
            event.wait(15)
        if route in ("redirect", "private-redirect"):
            target = f"/page/{key}"
            if route == "private-redirect":
                target = f"http://10.0.0.1:{self.server.server_port}/blocked/{key}"

            self.send_response(302)
            self.send_header("Location", target)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if route in ("sso-start", "sso-idp"):
            target = (f"http://localhost:{self.server.server_port}/sso-idp/{key}"
                      if route == "sso-start" else
                      f"http://127.0.0.1:{self.server.server_port}/sso-complete/{key}")
            self.send_response(302)
            self.send_header("Location", target)
            if route == "sso-idp":
                self.send_header("Set-Cookie", f"idp_session={key}; Path=/; HttpOnly; SameSite=Lax")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if route == "sso-complete":
            self.reply(
                b"<!doctype html><body>Signed in through the controlled identity provider</body>",
                "text/html",
                headers=[("Set-Cookie", f"vitrine_session={key}; Path=/; HttpOnly; SameSite=Lax")])
            return
        if route == "sso-private":
            authorized = event["sessionSeen"] == "true"
            self.reply(
                b"<!doctype html><body>Private synthetic page</body>" if authorized else
                b"<!doctype html><body>Sign in required</body>",
                "text/html", status=200 if authorized else 401)
            return
        if route == "resources":
            private = f"http://10.0.0.1:{self.server.server_port}"
            body = (f"<!doctype html><html><body><img src='/image/{key}'>"
                    f"<img src='{private}/image/{key}'>"
                    f"<link rel='stylesheet' href='{private}/style/{key}'>"
                    f"<script src='{private}/script/{key}'></script>"
                    f"<iframe src='{private}/frame/{key}'></iframe></body></html>")
            self.reply(body.encode(), "text/html")
            return
        if route == "image":
            self.reply(b"<svg xmlns='http://www.w3.org/2000/svg' width='8' height='8'>"
                       b"<rect width='8' height='8' fill='green'/></svg>", "image/svg+xml")
            return
        if route == "style":
            self.reply(b"body { color: green; }", "text/css")
            return
        if route == "script":
            self.reply(b"window.fixtureLoaded = true;", "application/javascript")
            return
        if route == "tall":
            self.reply(b"<!doctype html><body style='height:100000px;background:green'></body>", "text/html")
            return
        self.reply(b"<!doctype html><html><body style='background:#123456;color:white'>"
                   b"Controlled capture</body></html>", "text/html")

    def reply(self, body, content_type, *, status=200, headers=()):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for name, value in headers:
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation is an expected fixture outcome.


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port-file", type=Path, required=True)
    args = parser.parse_args()
    print("Binding loopback fixture", flush=True)
    with FixtureServer() as server:
        pending = args.port_file.with_suffix(".pending")
        pending.write_text(str(server.server_port))
        pending.replace(args.port_file)
        print(f"Loopback fixture ready on port {server.server_port}", flush=True)
        server.serve_forever()
