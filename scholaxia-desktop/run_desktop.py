"""
Scholaxia Desktop Launcher — Windows & tablet-friendly window sizing.
Uses WebView2 + local HTTP server (more reliable than file://).
"""

import os
import sys
import threading
import http.server
import socketserver

try:
    import webview
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pywebview", "-q"])
    import webview

ROOT = os.path.dirname(os.path.abspath(__file__))
RENDERER = os.path.join(ROOT, "renderer")
PORT = 17890


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RENDERER, **kwargs)

    def log_message(self, format, *args):
        pass


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

    t = threading.Thread(target=start_server, daemon=True)
    t.start()

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
