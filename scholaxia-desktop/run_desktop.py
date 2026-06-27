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
import base64
import hashlib
import hmac

try:
    import webview
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pywebview", "-q"])
    import webview

ROOT = os.path.dirname(os.path.abspath(__file__))
RENDERER = os.path.join(ROOT, "renderer")
PORT = 17890
DISCORD_PORT = 3001
DISCORD_DIR = os.path.normpath(os.path.join(ROOT, "..", "..", "discord-clone-nextjs"))
REMOTE_API = "https://scholaxia1.onrender.com"
STREAM_API_KEY = "7cu55d72xtjs"
STREAM_CHAT_SECRET = ""


def _parse_env_file(path):
    values = {}
    if not os.path.isfile(path):
        return values
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            values[key.strip()] = val.strip().strip('"').strip("'")
    return values


def load_stream_config():
    global STREAM_CHAT_SECRET
    for path in (
        os.path.join(ROOT, "stream.env"),
        os.path.join(DISCORD_DIR, ".env.local"),
    ):
        env = _parse_env_file(path)
        secret = env.get("STREAM_CHAT_SECRET", "").strip()
        if secret:
            STREAM_CHAT_SECRET = secret
            return secret
    STREAM_CHAT_SECRET = os.environ.get("STREAM_CHAT_SECRET", "").strip()
    return STREAM_CHAT_SECRET


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_stream_token(user_id: str, secret: str) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"user_id": user_id}).encode())
    signing_input = f"{header}.{payload}".encode()
    sig = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    return f"{header}.{payload}.{sig}"


load_stream_config()


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RENDERER, **kwargs)

    def log_message(self, format, *args):
        pass

    def end_headers(self):
        path = self.path.split("?", 1)[0]
        if path.endswith((".js", ".css", ".html")):
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
        super().end_headers()

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

    def _proxy_discord(self, method):
        url = f"http://127.0.0.1:{DISCORD_PORT}{self.path}"
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length) if length and method in ("POST", "PUT", "PATCH", "DELETE") else None
        headers = {}
        for header in ("Content-Type", "Accept", "Authorization", "Cookie"):
            value = self.headers.get(header)
            if value:
                headers[header] = value
        skip_response = {"transfer-encoding", "connection", "x-frame-options", "content-security-policy", "content-security-policy-report-only"}
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() in skip_response:
                        continue
                    self.send_header(key, value)
                self.send_header("X-Frame-Options", "SAMEORIGIN")
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as exc:
            payload = exc.read()
            self.send_response(exc.code)
            ct = exc.headers.get("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Type", ct)
            self.end_headers()
            self.wfile.write(payload)
        except Exception as exc:
            self.send_response(502)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = (
                "<h2>Community server not running</h2>"
                "<p>Start Discord: run START-DISCORD.bat or <code>npm run dev</code> in discord-clone-nextjs</p>"
                f"<p><small>{exc}</small></p>"
            ).encode("utf-8")
            self.wfile.write(msg)

    def _community_stream_token(self):
        secret = load_stream_config()
        if not secret:
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "error": "Add STREAM_CHAT_SECRET to scholaxia-desktop/stream.env (from getstream.io dashboard)."
                    }
                ).encode("utf-8")
            )
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = {}
        if length:
            try:
                body = json.loads(self.rfile.read(length).decode("utf-8"))
            except Exception:
                body = {}
        user_id = str(body.get("userId") or "").strip()
        name = str(body.get("name") or "Student").strip() or "Student"
        if not user_id:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "userId required"}).encode("utf-8"))
            return
        token = make_stream_token(user_id, secret)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(
            json.dumps(
                {"userId": user_id, "token": token, "apiKey": STREAM_API_KEY, "name": name}
            ).encode("utf-8")
        )

    def do_OPTIONS(self):
        if self.path.split("?", 1)[0] == "/community/stream-token":
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
            self.end_headers()
            return
        if self.path.startswith("/api-proxy/"):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
            self.end_headers()
            return
        if self.path.startswith("/discord-app"):
            self.send_response(204)
            self.end_headers()
            return
        super().do_OPTIONS()

    def do_GET(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("GET")
            return
        if self.path.startswith("/discord-app"):
            self._proxy_discord("GET")
            return
        super().do_GET()

    def do_POST(self):
        if self.path.split("?", 1)[0] == "/community/stream-token":
            self._community_stream_token()
            return
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("POST")
            return
        if self.path.startswith("/discord-app"):
            self._proxy_discord("POST")
            return
        super().do_POST()

    def do_PATCH(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("PATCH")
            return
        if self.path.startswith("/discord-app"):
            self._proxy_discord("PATCH")
            return
        self.send_error(405)

    def do_PUT(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("PUT")
            return
        if self.path.startswith("/discord-app"):
            self._proxy_discord("PUT")
            return
        self.send_error(405)

    def do_DELETE(self):
        if self.path.startswith("/api-proxy/"):
            self._proxy_api("DELETE")
            return
        if self.path.startswith("/discord-app"):
            self._proxy_discord("DELETE")
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


def discord_project_ready():
    return os.path.isdir(DISCORD_DIR) and os.path.isfile(os.path.join(DISCORD_DIR, "package.json"))


def discord_port_listening():
    try:
        with socket.create_connection(("127.0.0.1", DISCORD_PORT), timeout=1):
            return True
    except OSError:
        return False


def start_discord_server():
    """Start discord-clone-nextjs on port 3001 for Community iframe."""
    if not discord_project_ready():
        print(f"Discord clone not found at {DISCORD_DIR} — Community tab needs it.")
        return False
    if discord_port_listening():
        print(f"Discord Community already running on port {DISCORD_PORT}.")
        return True

    npm_cmd = "npm.cmd" if sys.platform == "win32" else "npm"
    print(f"Starting Discord Community on http://127.0.0.1:{DISCORD_PORT} …")
    env = os.environ.copy()
    secret = load_stream_config()
    if secret:
        env["STREAM_CHAT_SECRET"] = secret
    try:
        subprocess.Popen(
            [npm_cmd, "run", "dev", "--", "-p", str(DISCORD_PORT)],
            cwd=DISCORD_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            shell=False,
            env=env,
        )
    except Exception as exc:
        print(f"Could not start Discord Community: {exc}")
        return False

    deadline = time.time() + 45
    while time.time() < deadline:
        if discord_port_listening():
            print(f"Discord Community ready — edit UI in discord-clone-nextjs/")
            return True
        time.sleep(0.5)
    print(
        f"Discord Community did not start in time. Run manually:\n"
        f'  cd "{DISCORD_DIR}"\n'
        f"  npm run dev -- -p {DISCORD_PORT}\n"
    )
    return False


def discord_proxy_ready():
    """True if /discord-app is forwarded (not 404 from static file server)."""
    try:
        with urllib.request.urlopen(
            f"http://127.0.0.1:{PORT}/discord-app/scholaxia",
            timeout=3,
        ) as resp:
            return resp.status < 500
    except urllib.error.HTTPError as exc:
        return exc.code != 404
    except Exception:
        return False


def ensure_server():
    """Start the local server once; reuse it when Student + Teacher are both open."""
    if proxy_is_ready() and discord_proxy_ready():
        print(f"Scholaxia server already running on port {PORT} — opening another portal window.")
        return True

    if port_is_listening():
        print("Replacing old desktop server (missing Community proxy)…")
        free_port(PORT)
        time.sleep(0.4)

    t = threading.Thread(target=start_server, daemon=True)
    t.start()

    if not wait_for_proxy():
        return False

    if discord_proxy_ready():
        print(f"Community proxy ready — http://127.0.0.1:{PORT}/discord-app/")
    else:
        print(f"WARNING: Community proxy missing on port {PORT}. Close all Scholaxia windows and restart.")

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

    if not load_stream_config():
        print(
            "NOTE: Community chat needs STREAM_CHAT_SECRET.\n"
            f'  Copy "{os.path.join(ROOT, "stream.env.example")}" to stream.env and add your GetStream secret.\n'
        )

    if not is_teacher and not is_admin:
        threading.Thread(target=start_discord_server, daemon=True).start()

    if is_teacher:
        page, title, bg = "teacher.html", "Scholaxia Teacher Portal", "#0a1410"
    elif is_admin:
        page, title, bg = "admin.html", "Scholaxia Admin Console", "#0a1410"
    else:
        page, title, bg = "app.html", "Scholaxia Student", "#0d1f14"

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
