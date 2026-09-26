#!/usr/bin/env python3
import html
import json
import mimetypes
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path("/srv/relay")
PUBLIC = ROOT / "public"
LISTEN = ("0.0.0.0", 8080)


class RelayHandler(BaseHTTPRequestHandler):
    server_version = "BlackglassRelay/4.7"

    def send_bytes(self, status, payload, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def send_text(self, status, text, content_type="text/plain; charset=utf-8"):
        self.send_bytes(status, text.encode("utf-8"), content_type)

    def do_GET(self):
        parsed = urlsplit(self.path)

        if parsed.path == "/healthz":
            self.send_bytes(
                200,
                json.dumps({"status": "ok"}).encode("utf-8"),
                "application/json",
            )
            return

        if parsed.path == "/":
            page = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Blackglass Artifact Relay</title>
  <style>
    body { background:#080d14; color:#d8e4ef; font-family:system-ui,sans-serif; margin:0; }
    main { max-width:850px; margin:7vh auto; padding:2.5rem; background:#101a25; border:1px solid #25374a; }
    h1 { color:#7fd8ff; letter-spacing:.08em; }
    code,a { color:#f6c177; }
    .status { padding:.7rem 1rem; background:#102d25; border-left:4px solid #5bd69b; }
    .muted { color:#8ea1b5; }
  </style>
</head>
<body><main>
  <h1>BLACKGLASS ARTIFACT RELAY</h1>
  <p class="status">External synchronization is operational.</p>
  <p>Approved release documents may be fetched through the download gateway.</p>
  <p><a href="/download?file=public/release-manifest.txt">Current release manifest</a></p>
  <p class="muted">Relay build 4.7.18 / compatibility decoding enabled</p>
</main></body></html>"""
            self.send_text(200, page, "text/html; charset=utf-8")
            return

        if parsed.path == "/download":
            self.handle_download(parsed.query)
            return

        self.send_text(404, "Not found\n")

    def handle_download(self, raw_query):
        raw_value = None
        for item in raw_query.split("&"):
            key, separator, value = item.partition("=")
            if separator and key == "file":
                raw_value = value
                break

        if raw_value is None:
            self.send_text(400, "Missing file parameter\n")
            return

        first_decode = unquote(raw_value)

        # Compatibility validation was added before legacy double decoding.
        # The second decode is the intentional challenge flaw.
        if not first_decode.startswith("public/") or ".." in first_decode:
            self.send_text(403, "Only public release paths are permitted\n")
            return

        legacy_path = unquote(first_decode)
        target = (ROOT / legacy_path).resolve()

        try:
            if not target.is_file():
                raise FileNotFoundError
            payload = target.read_bytes()
        except (FileNotFoundError, PermissionError, OSError):
            self.send_text(404, "Artifact not found\n")
            return

        content_type = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
        safe_name = html.escape(os.path.basename(target))
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Disposition", f'attachment; filename="{safe_name}"')
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, message_format, *args):
        print(
            f'{self.client_address[0]} - "{message_format % args}"',
            flush=True,
        )


if __name__ == "__main__":
    HTTPServer(LISTEN, RelayHandler).serve_forever()

