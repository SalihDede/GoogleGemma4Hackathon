from __future__ import annotations

import argparse
import html
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ESP_BASE = "http://192.168.4.2"
DEFAULT_PORT = 8765


PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ESP32-CAM Debug</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 18px; font-family: Arial, sans-serif; background: #101418; color: #eef2f6; }
    h1 { margin: 0 0 10px; font-size: 28px; }
    .bar { display: flex; flex-wrap: wrap; gap: 8px; margin: 14px 0; }
    button { font-size: 15px; padding: 10px 12px; border: 0; border-radius: 6px; background: #38bdf8; color: #061018; cursor: pointer; }
    button.secondary { background: #9ca3af; }
    button.danger { background: #f87171; }
    img { display: block; max-width: min(100%, 900px); margin-top: 12px; border-radius: 6px; background: #222; }
    pre { max-width: 900px; min-height: 140px; white-space: pre-wrap; overflow: auto; background: #1b222b; padding: 12px; border-radius: 6px; }
    .row { display: grid; grid-template-columns: minmax(0, 1fr); gap: 14px; }
    .hint { color: #cbd5e1; line-height: 1.45; }
    code { color: #bae6fd; }
  </style>
</head>
<body>
  <h1>ESP32-CAM Debug</h1>
  <div class="hint">
    ESP target: <code>http://192.168.4.2</code>.
    Direct buttons hit the ESP from your browser. Proxy buttons hit ESP through this localhost server.
  </div>

  <div class="bar">
    <button onclick="statusProxy()">Status via localhost proxy</button>
    <button onclick="captureProxy()">Capture via localhost proxy</button>
    <button onclick="captureDirect()">Capture direct ESP image</button>
    <button onclick="rootProxy()" class="secondary">Root page via proxy</button>
    <button onclick="clearLog()" class="danger">Clear</button>
  </div>

  <div class="row">
    <pre id="log">Ready.</pre>
    <img id="photo" alt="capture preview">
  </div>

  <script>
    const logEl = document.getElementById('log');
    const photo = document.getElementById('photo');

    function log(message) {
      const now = new Date().toLocaleTimeString();
      logEl.textContent = `[${now}] ${message}\\n\\n` + logEl.textContent;
    }

    function clearLog() {
      logEl.textContent = 'Ready.';
      photo.removeAttribute('src');
    }

    async function statusProxy() {
      const started = performance.now();
      try {
        const r = await fetch('/api/status?t=' + Date.now(), { cache: 'no-store' });
        const text = await r.text();
        log(`STATUS proxy HTTP ${r.status} in ${Math.round(performance.now() - started)}ms\\n${text}`);
      } catch (e) {
        log('STATUS proxy failed: ' + e);
      }
    }

    async function rootProxy() {
      const started = performance.now();
      try {
        const r = await fetch('/api/root?t=' + Date.now(), { cache: 'no-store' });
        const text = await r.text();
        log(`ROOT proxy HTTP ${r.status} in ${Math.round(performance.now() - started)}ms\\n${text.slice(0, 1200)}`);
      } catch (e) {
        log('ROOT proxy failed: ' + e);
      }
    }

    async function captureProxy() {
      const started = performance.now();
      try {
        const r = await fetch('/api/capture?t=' + Date.now(), { cache: 'no-store' });
        const type = r.headers.get('content-type') || '';
        const size = r.headers.get('x-esp-bytes') || r.headers.get('content-length') || 'unknown';
        if (!r.ok) {
          log(`CAPTURE proxy HTTP ${r.status}, type=${type}, bytes=${size}\\n${await r.text()}`);
          return;
        }
        const blob = await r.blob();
        photo.src = URL.createObjectURL(blob);
        log(`CAPTURE proxy OK in ${Math.round(performance.now() - started)}ms, type=${type}, bytes=${blob.size}`);
      } catch (e) {
        log('CAPTURE proxy failed: ' + e);
      }
    }

    function captureDirect() {
      const url = 'http://192.168.4.2/capture?t=' + Date.now();
      photo.onload = () => log('CAPTURE direct image loaded: ' + url);
      photo.onerror = () => log('CAPTURE direct image failed: ' + url);
      photo.src = url;
      log('CAPTURE direct requested: ' + url);
    }
  </script>
</body>
</html>
"""


class EspDebugHandler(BaseHTTPRequestHandler):
    server_version = "EspCamDebug/1.0"

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            self._send_text(200, "text/html; charset=utf-8", PAGE)
            return
        if path == "/api/status":
            self._proxy_text("/status")
            return
        if path == "/api/root":
            self._proxy_text("/")
            return
        if path == "/api/capture":
            self._proxy_capture()
            return
        self._send_text(404, "text/plain; charset=utf-8", "not found")

    def log_message(self, fmt: str, *args: object) -> None:
        print("%s - %s" % (self.log_date_time_string(), fmt % args))

    def _proxy_text(self, endpoint: str) -> None:
        try:
            body, status, headers = self._fetch(endpoint, timeout=5)
            content_type = headers.get("content-type", "text/plain; charset=utf-8")
            self._send_bytes(status, content_type, body)
        except Exception as exc:
            self._send_json_error(exc)

    def _proxy_capture(self) -> None:
        try:
            body, status, headers = self._fetch(f"/capture?t={int(time.time() * 1000)}", timeout=10)
            content_type = headers.get("content-type", "application/octet-stream")
            if status != 200:
                self._send_bytes(status, content_type, body)
                return
            if not body.startswith(b"\\xff\\xd8"):
                self._send_text(
                    502,
                    "text/plain; charset=utf-8",
                    f"ESP response is not a JPEG. content-type={content_type}\\n\\n"
                    + body[:1200].decode("utf-8", errors="replace"),
                )
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-ESP-Bytes", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:
            self._send_json_error(exc)

    def _fetch(self, endpoint: str, *, timeout: int) -> tuple[bytes, int, dict[str, str]]:
        request = Request(
            ESP_BASE + endpoint,
            headers={
                "Connection": "close",
                "Cache-Control": "no-cache",
                "User-Agent": "EspCamDebug/1.0",
            },
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                return response.read(), response.status, dict(response.headers)
        except HTTPError as exc:
            return exc.read(), exc.code, dict(exc.headers)
        except URLError as exc:
            raise RuntimeError(str(exc.reason)) from exc

    def _send_json_error(self, exc: Exception) -> None:
        body = json.dumps(
            {"ok": False, "error": type(exc).__name__, "message": str(exc)},
            ensure_ascii=True,
            indent=2,
        ).encode("utf-8")
        self._send_bytes(502, "application/json; charset=utf-8", body)

    def _send_text(self, status: int, content_type: str, text: str) -> None:
        self._send_bytes(status, content_type, text.encode("utf-8"))

    def _send_bytes(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    parser = argparse.ArgumentParser(description="Local ESP32-CAM debug server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), EspDebugHandler)
    print(f"ESP32-CAM debug server: http://{args.host}:{args.port}")
    print(f"Proxying ESP target: {ESP_BASE}")
    server.serve_forever()


if __name__ == "__main__":
    main()
