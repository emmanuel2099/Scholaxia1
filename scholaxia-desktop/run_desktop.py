"""
Scholaxia Student — Windows Desktop Launcher
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


def main():
    import sys
    is_admin = "--admin" in sys.argv

    if not os.path.isfile(os.path.join(RENDERER, "index.html")):
        print("Missing renderer/index.html")
        sys.exit(1)

    t = threading.Thread(target=start_server, daemon=True)
    t.start()

    page = "admin.html" if is_admin else "index.html"
    title = "Scholaxia Admin Console" if is_admin else "Scholaxia Student Portal"
    url = f"http://127.0.0.1:{PORT}/{page}"
    window = webview.create_window(
        title=title,
        url=url,
        width=1280,
        height=800,
        min_size=(1024, 680),
        background_color="#0d1f14" if not is_admin else "#0a1410",
    )
    webview.start(debug=False)


if __name__ == "__main__":
    main()
