#!/usr/bin/env python3

import argparse
import json
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


class IsolatedHandler(SimpleHTTPRequestHandler):
    local_assets = {}

    def log_message(self, format, *args):
        return

    def do_GET(self):
        if self.path == "/__xemu_assets__/manifest.json":
            self.send_asset_manifest()
            return
        if self.path.startswith("/__xemu_assets__/"):
            self.send_asset_file(head_only=False)
            return
        super().do_GET()

    def do_HEAD(self):
        if self.path == "/__xemu_assets__/manifest.json":
            self.send_asset_manifest(head_only=True)
            return
        if self.path.startswith("/__xemu_assets__/"):
            self.send_asset_file(head_only=True)
            return
        super().do_HEAD()

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_asset_manifest(self, head_only=False):
        assets = []
        for key, path in self.local_assets.items():
            exists = path.is_file()
            stat = path.stat() if exists else None
            assets.append({
                "key": key,
                "name": path.name,
                "available": exists,
                "size": stat.st_size if stat else 0,
                "url": f"/__xemu_assets__/{key}",
            })

        body = json.dumps({"assets": assets}, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def send_asset_file(self, head_only=False):
        key = unquote(urlparse(self.path).path.rsplit("/", 1)[-1])
        path = self.local_assets.get(key)
        if path is None:
            self.send_error(404, "unknown xemu asset")
            return
        if not path.is_file():
            self.send_error(404, "xemu asset missing")
            return

        stat = path.stat()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(stat.st_size))
        self.send_header("Content-Disposition", f'attachment; filename="{path.name}"')
        self.end_headers()
        if head_only:
            return

        with path.open("rb") as asset:
            while True:
                chunk = asset.read(1024 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)


def env_path(*names, default):
    for name in names:
        value = os.environ.get(name)
        if value:
            return Path(value).expanduser()
    return Path(default)


def local_asset_paths():
    return {
        "mcpx": env_path(
            "XEMU_BROWSER_MCPX",
            "XEMU_MCPX",
            default="/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin",
        ),
        "flash": env_path(
            "XEMU_BROWSER_FLASH",
            "XEMU_FLASH",
            default="/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin",
        ),
        "eeprom": env_path(
            "XEMU_BROWSER_EEPROM",
            "XEMU_EEPROM",
            default="/tmp/xemu-b6-eeprom.bin",
        ),
        "hdd": env_path(
            "XEMU_BROWSER_HDD",
            "XEMU_HDD",
            default="/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2",
        ),
    }


def main():
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", default=str(repo_root))
    args = parser.parse_args()

    handler = partial(IsolatedHandler, directory=args.directory)
    IsolatedHandler.local_assets = local_asset_paths()
    server = ThreadingHTTPServer((args.host, args.port), handler)
    url = f"http://{args.host}:{args.port}/browser/xbox-boot/"
    print(f"Serving xemu browser boot at {url}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
