#!/usr/bin/env python3

import argparse
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


class IsolatedHandler(SimpleHTTPRequestHandler):
    smoke_asset_env = {
        "flash": "XEMU_FLASH",
        "mcpx": "XEMU_MCPX",
        "eeprom": "XEMU_EEPROM",
        "hdd": "XEMU_HDD",
        "dvd": "XEMU_DVD",
    }

    def do_GET(self):
        if self.path.startswith("/__xemu_smoke_asset/"):
            self.send_smoke_asset(send_body=True)
            return
        super().do_GET()

    def do_HEAD(self):
        if self.path.startswith("/__xemu_smoke_asset/"):
            self.send_smoke_asset(send_body=False)
            return
        super().do_HEAD()

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_smoke_asset(self, send_body):
        key = unquote(urlparse(self.path).path.removeprefix("/__xemu_smoke_asset/"))
        env_name = self.smoke_asset_env.get(key)
        if env_name is None:
            self.send_error(404, "unknown smoke asset")
            return

        path = os.environ.get(env_name, "")
        if not path:
            self.send_error(404, "smoke asset not configured")
            return

        asset_path = Path(path)
        if not asset_path.is_file():
            self.send_error(404, "smoke asset missing")
            return

        size = asset_path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("X-Xemu-Asset-Name", key)
        self.send_header("X-Xemu-Asset-Filename", asset_path.name)
        self.end_headers()

        if send_body:
            with asset_path.open("rb") as asset_file:
                while True:
                    chunk = asset_file.read(1024 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)


def main():
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", default=str(repo_root))
    args = parser.parse_args()

    handler = partial(IsolatedHandler, directory=args.directory)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    url = f"http://{args.host}:{args.port}/browser/xbox-boot/"
    print(f"BROWSER_BOOT_SERVER url={url} directory={args.directory}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
