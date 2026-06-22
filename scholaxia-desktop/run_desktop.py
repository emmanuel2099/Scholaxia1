"""
Scholaxia Desktop Launcher — Windows & tablet-friendly window sizing.
Uses WebView2 + local HTTP server (more reliable than file://).
API requests are proxied through localhost so WebView2 can reach Render reliably.
"""

import json
import os
import sys
import time
import threading
import http.server
import socketserver
import socket
import subprocess
import urllib.error
import urllib.request

try:
    import webview
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pywebview", "-q"])
    import webview

ROOT = os.path.dirname(os.path.abspath(__file__))
RENDERER = os.path.join(ROOT, "renderer")
PORT = 17890
REMOTE_API = "https://scholaxia1.onrender.com"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RENDERER, **kwargs)

    def log_message(self, format, *args):
        pass

    def _proxy_api(self, method):
        remote_path = self.path[len("/api-proxy") :]
        if not remote_path.startswith("/"):
            remote_path = "/" + remote_path
        url = REMOTE_API + remote_path
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length else None
        headers = {}
        content_type = self.headers.get("Content-Type")
        if content_type:
            headers["Content-Type"] = content_type
        auth = self.headers.get("Authorization")
        if auth:
            headers["Authorization"] = auth
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
                self.send_response(resp.status)
                ct = resp.headers.get("Content-Type", "application/json")
                self.send_header("Content-Type", ct)
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            self.send_response(exc.code)
            self.send_header("Content-Type", exc.headers.get("Content-Type", "application/json"))
            self.end_headers()
            self.wfile.write(payload)
        except Exception as exc:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"detail": f"API proxy error: {exc}"}).encode("utf-8"))

    def do_OPTIONS(self):
        if self.path.startswith("/api-proxy/"):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
            self.end_headers()
            return
        super().do_OPTIONS()

    def do_GET(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("GET")
            return
        super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("POST")
            return
        super().do_POST()

    def do_PATCH(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("PATCH")
            return
        self.send_error(405)

    def do_PUT(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("PUT")
            return
        self.send_error(405)

    def do_DELETE(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("DELETE")
            return
        self.send_error(405)


def free_port(port):
    """Stop any process already listening on our desktop port (old server without API proxy)."""
    if sys.platform != "win32":
        return
    try:
        out = subprocess.check_output(
            f"netstat -ano | findstr :{port}",
            shell=True,
            text=True,
            errors="ignore",
        )
    except Exception:
        return
    my_pid = os.getpid()
    for line in out.splitlines():
        if "LISTENING" not in line:
            continue
        parts = line.split()
        if not parts:
            continue
        pid = parts[-1]
        if not pid.isdigit():
            continue
        pid = int(pid)
        if pid == my_pid:
            continue
        print(f"Stopping old Scholaxia desktop server (PID {pid}) on port {port}…")
        subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)


def proxy_is_ready():
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/api-proxy/health", timeout=2) as resp:
            return resp.status == 200
    except Exception:
        return False


def port_is_listening():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=1):
            return True
    except OSError:
        return False


def wait_for_proxy(timeout_sec=15):
    """Ensure the local API proxy is running before WebView loads."""
    deadline = time.time() + timeout_sec
    url = f"http://127.0.0.1:{PORT}/api-proxy/health"
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                if resp.status == 200:
                    return True
        except Exception:
            time.sleep(0.25)
    return False


def ensure_server():
    """Start the local server once; reuse it when Student + Teacher are both open."""
    if proxy_is_ready():
        print(f"Scholaxia server already running on port {PORT} — opening another portal window.")
        return True

    if port_is_listening():
        print("Replacing old desktop server (missing API proxy)…")
        free_port(PORT)
        time.sleep(0.4)

    t = threading.Thread(target=start_server, daemon=True)
    t.start()

    if not wait_for_proxy():
        return False

    print(f"Scholaxia desktop ready — API proxy active on http://127.0.0.1:{PORT}/api-proxy")
    return True


def start_server():
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), Handler)
    httpd.serve_forever()


def get_screen_size():
    """Best-effort screen size for Windows tablets and laptops."""
    try:
        import ctypes
        user32 = ctypes.windll.user32
        return user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
    except Exception:
        return 1280, 800


def get_window_size():
    screen_w, screen_h = get_screen_size()
    width = min(1280, max(900, int(screen_w * 0.92)))
    height = min(860, max(640, int(screen_h * 0.9)))
    min_w = min(768, width)
    min_h = min(600, height)
    return width, height, (min_w, min_h)


def main():
    is_admin = "--admin" in sys.argv
    is_teacher = "--teacher" in sys.argv

    if not os.path.isfile(os.path.join(RENDERER, "index.html")):
        print("Missing renderer/index.html")
        sys.exit(1)

    if not ensure_server():
        print(
            f"\nERROR: Scholaxia desktop server did not start on port {PORT}.\n"
            "Close all Scholaxia windows and try again.\n"
        )
        sys.exit(1)

    if is_teacher:
        page, title, bg = "teacher.html", "Scholaxia Teacher Portal", "#0a1410"
    elif is_admin:
        page, title, bg = "admin.html", "Scholaxia Admin Console", "#0a1410"
    else:
        page, title, bg = "index.html", "Scholaxia Student Portal", "#0d1f14"

    url = f"http://127.0.0.1:{PORT}/{page}"
    width, height, min_size = get_window_size()

    window = webview.create_window(
        title=title,
        url=url,
        width=width,
        height=height,
        min_size=min_size,
        resizable=True,
        fullscreen=False,
        background_color=bg,
    )
    webview.start(debug=False)


if __name__ == "__main__":
    main()
