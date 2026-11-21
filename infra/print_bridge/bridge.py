#!/usr/bin/env python3
"""جسر طباعة حرارية محلي لـ NABOO Web.

يشغَّل على جهاز الكاشير بجانب المتصفح، ويستقبل ESC/POS من تطبيق الويب
ثم يرسله عبر TCP إلى الطابعة على الشبكة المحلية.

الاستخدام:
  python3 bridge.py
  # أو: PORT=19100 python3 bridge.py

POST http://127.0.0.1:19100/print
JSON: { "host": "192.168.1.50", "port": 9100, "payloadBase64": "..." }
"""

from __future__ import annotations

import base64
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


BRIDGE_PORT = int(os.environ.get("PORT", "19100"))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"[naboo-print-bridge] {self.address_string()} - {fmt % args}")

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS, GET")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Accept")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        body = b'{"ok":true,"service":"naboo-print-bridge"}\n'
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != "/print":
            self.send_error(404, "Not Found")
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
            host = str(data.get("host", "")).strip()
            port = int(data.get("port", 9100))
            payload = base64.b64decode(data.get("payloadBase64", ""))
            if not host or not payload:
                raise ValueError("host/payload required")
            with socket.create_connection((host, port), timeout=5.0) as sock:
                sock.sendall(payload)
            out = b'{"ok":true}\n'
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
        except Exception as exc:  # noqa: BLE001
            msg = json.dumps({"ok": False, "error": str(exc)}).encode("utf-8")
            self.send_response(502)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", BRIDGE_PORT), Handler)
    print(f"NABOO print bridge listening on http://127.0.0.1:{BRIDGE_PORT}/print")
    server.serve_forever()


if __name__ == "__main__":
    main()
