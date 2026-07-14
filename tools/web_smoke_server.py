#!/usr/bin/env python3
"""COOP/COEP static server for the Godot 4 web build (SharedArrayBuffer
needs cross-origin isolation — a plain http.server can't boot the engine).
Usage: python3 tools/web_smoke_server.py [port] [dir]"""
import http.server, functools, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, *a):
        pass

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8371
    directory = sys.argv[2] if len(sys.argv) > 2 else "builds/web"
    handler = functools.partial(Handler, directory=directory)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
