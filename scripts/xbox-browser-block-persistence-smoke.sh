#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-block-persistence-smoke.sh

Starts the isolated browser boot server, opens the shell in Playwright Chromium,
and verifies that browser block dirty snapshots can round-trip through
IndexedDB and restore bytes over the same base image.

Controls:
  XEMU_BROWSER_BLOCK_PERSISTENCE_PORT     Local server port. Default: 8786.
  XEMU_BROWSER_BLOCK_PERSISTENCE_TIMEOUT  Playwright timeout ms. Default: 15000.
  XEMU_BROWSER_RUNTIME_CHANNEL            Playwright browser channel. Default: auto.
  NODE_BIN                                Node executable override.
  NODE_PATH                               Extra Node module lookup path.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
port="${XEMU_BROWSER_BLOCK_PERSISTENCE_PORT:-8786}"
timeout_ms="${XEMU_BROWSER_BLOCK_PERSISTENCE_TIMEOUT:-15000}"
browser_channel="${XEMU_BROWSER_RUNTIME_CHANNEL:-}"
node_bin="${NODE_BIN:-node}"

codex_node="/Users/samuelalaniz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
codex_modules="/Users/samuelalaniz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules"
if [ "${node_bin}" = "node" ] && [ -x "${codex_node}" ]; then
    node_bin="${codex_node}"
fi
if [ -d "${codex_modules}" ]; then
    export NODE_PATH="${codex_modules}${NODE_PATH:+:${NODE_PATH}}"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-browser-block-persistence.XXXXXX")"
trap 'rm -rf "${tmp_dir}"; if [ -n "${server_pid:-}" ]; then kill "${server_pid}" >/dev/null 2>&1 || true; wait "${server_pid}" >/dev/null 2>&1 || true; fi' EXIT

server_log="${tmp_dir}/server.log"
smoke_script="${tmp_dir}/block-persistence-smoke.mjs"
base_url="http://127.0.0.1:${port}"
page_url="${base_url}/browser/xbox-boot/"

python3 "${repo_root}/scripts/serve-xbox-browser-boot.py" --port "${port}" >"${server_log}" 2>&1 &
server_pid="$!"

for _ in $(seq 1 50); do
    if curl -fsSI "${page_url}" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
        printf 'BROWSER_BLOCK_PERSISTENCE_SMOKE result=fail reason=server-exited log=%s\n' "${server_log}" >&2
        cat "${server_log}" >&2
        exit 1
    fi
    sleep 0.1
done

if ! curl -fsSI "${page_url}" >/dev/null 2>&1; then
    printf 'BROWSER_BLOCK_PERSISTENCE_SMOKE result=fail reason=server-not-ready log=%s\n' "${server_log}" >&2
    cat "${server_log}" >&2
    exit 1
fi

cat >"${smoke_script}" <<'EOF'
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const pageUrl = process.env.XEMU_BROWSER_BLOCK_PERSISTENCE_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_BLOCK_PERSISTENCE_TIMEOUT || "15000");
const browserChannel = process.env.XEMU_BROWSER_RUNTIME_CHANNEL || "";

function fail(reason, detail = "") {
  console.error(`BROWSER_BLOCK_PERSISTENCE_SMOKE result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
  process.exit(1);
}

const launchOptions = {
  headless: true,
  args: ["--no-sandbox"],
};
if (browserChannel) {
  launchOptions.channel = browserChannel;
} else if (process.platform === "darwin") {
  const { existsSync } = require("node:fs");
  if (existsSync("/Applications/Google Chrome.app")) {
    launchOptions.channel = "chrome";
  }
}

const browser = await chromium.launch(launchOptions);

try {
  const context = await browser.newContext();
  const page = await context.newPage();
  page.setDefaultTimeout(timeoutMs);

  await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
  const result = await page.evaluate(async () => {
    const dbName = "xemu.browserBoot.blockSnapshots.v1";
    const storeName = "snapshots";
    const blockKey = "hdd";

    function openDb() {
      return new Promise((resolve, reject) => {
        const request = indexedDB.open(dbName, 1);
        request.onupgradeneeded = () => {
          const db = request.result;
          if (!db.objectStoreNames.contains(storeName)) {
            db.createObjectStore(storeName, { keyPath: "key" });
          }
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error("open failed"));
      });
    }

    function deleteDb() {
      return new Promise((resolve, reject) => {
        const request = indexedDB.deleteDatabase(dbName);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error || new Error("delete failed"));
        request.onblocked = () => reject(new Error("delete blocked"));
      });
    }

    function putRecord(db, record) {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readwrite");
        tx.objectStore(storeName).put(record);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error || new Error("put failed"));
        tx.onabort = () => reject(tx.error || new Error("put aborted"));
      });
    }

    function getRecord(db, key) {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readonly");
        const request = tx.objectStore(storeName).get(key);
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(request.error || new Error("get failed"));
      });
    }

    await deleteDb().catch(() => {});
    const {
      SyncMemoryBlockDevice,
      chunksFromOverlaySnapshot,
    } = await import("./block-storage.mjs");

    const imageSize = 1024 * 1024;
    const base = new Uint8Array(imageSize);
    for (let i = 0; i < base.length; i++) {
      base[i] = (i * 29 + (i >>> 5) * 11 + 0x42) & 0xff;
    }

    const device = new SyncMemoryBlockDevice(base.slice(), { name: "browser-idb-smoke", chunkSize: 4096 });
    const writeOffset = 4096 * 9 - 31;
    const writeBytes = new Uint8Array(4096 * 2 + 177);
    for (let i = 0; i < writeBytes.length; i++) {
      writeBytes[i] = (0x77 ^ (i * 17) ^ (i >>> 2)) & 0xff;
    }
    device.writeFrom(writeBytes, writeOffset);

    const snapshot = device.flushSnapshot();
    if (!snapshot || snapshot.chunks.length === 0) {
      throw new Error("missing snapshot");
    }
    const serialized = JSON.stringify(snapshot);

    const db = await openDb();
    await putRecord(db, {
      key: blockKey,
      name: "xbox_hdd.img",
      size: base.byteLength,
      backend: "memory",
      updatedAt: Date.now(),
      serializedBytes: serialized.length,
      snapshot,
    });
    const record = await getRecord(db, blockKey);
    db.close();
    if (!record || !record.snapshot) {
      throw new Error("missing persisted record");
    }

    const restored = base.slice();
    const chunks = chunksFromOverlaySnapshot(record.snapshot, { size: restored.byteLength });
    for (const [start, bytes] of chunks) {
      restored.set(bytes, start);
    }

    for (let i = 0; i < writeBytes.length; i++) {
      if (restored[writeOffset + i] !== writeBytes[i]) {
        throw new Error(`readback mismatch at ${i}`);
      }
    }

    return {
      chunks: chunks.length,
      serializedBytes: serialized.length,
      bytesWritten: writeBytes.length,
    };
  });

  console.log([
    "BROWSER_BLOCK_PERSISTENCE_SMOKE",
    "result=pass",
    "target=indexedDB",
    `chunks=${result.chunks}`,
    `serialized_bytes=${result.serializedBytes}`,
    `bytes_written=${result.bytesWritten}`,
    "readback=yes",
  ].join(" "));
} finally {
  await browser.close();
}
EOF

smoke_driver_script="${smoke_script}"
if ! "${node_bin}" -e 'require.resolve("playwright")' >/dev/null 2>&1; then
    smoke_driver_script="${repo_root}/scripts/xbox-browser-block-persistence-firefox-bidi.mjs"
fi

XEMU_BROWSER_BLOCK_PERSISTENCE_PAGE_URL="${page_url}" \
XEMU_BROWSER_BLOCK_PERSISTENCE_TIMEOUT="${timeout_ms}" \
XEMU_BROWSER_RUNTIME_CHANNEL="${browser_channel}" \
    "${node_bin}" "${smoke_driver_script}"
