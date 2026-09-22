#!/usr/bin/env python3
"""Loopback-only WebKit fixture proxy. Never resolve or forward a destination."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Event, Lock
from urllib.parse import urlsplit


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

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
        with self.server.lock:
            self.server.events.append({"host": host, "path": path})
        route, _, key = path.lstrip("/").partition("/")
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

    def reply(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation is an expected fixture outcome.


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port-file", type=Path, required=True)
    args = parser.parse_args()
    with FixtureServer() as server:
        args.port_file.write_text(str(server.server_port))
        server.serve_forever()
