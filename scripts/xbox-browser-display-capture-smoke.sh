#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-display-capture-smoke.sh

Starts the isolated browser boot server, opens the browser shell in Playwright
Chromium, triggers the deterministic synthetic framebuffer capture path, and
validates the emitted B4 display evidence contract. This proves the browser
host can capture and hash a non-empty canvas; it does not prove real Xbox B4.

Controls:
  XEMU_BROWSER_DISPLAY_CAPTURE_PORT     Local server port. Default: 8789.
  XEMU_BROWSER_DISPLAY_CAPTURE_TIMEOUT  Page timeout ms. Default: 15000.
  XEMU_BROWSER_RUNTIME_CHANNEL          Playwright browser channel. Default: auto.
  NODE_BIN                              Node executable override.
  NODE_PATH                             Extra Node module lookup path.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
port="${XEMU_BROWSER_DISPLAY_CAPTURE_PORT:-8789}"
timeout_ms="${XEMU_BROWSER_DISPLAY_CAPTURE_TIMEOUT:-15000}"
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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-browser-display-capture.XXXXXX")"
trap 'rm -rf "${tmp_dir}"; if [ -n "${server_pid:-}" ]; then kill "${server_pid}" >/dev/null 2>&1 || true; wait "${server_pid}" >/dev/null 2>&1 || true; fi' EXIT

server_log="${tmp_dir}/server.log"
capture_script="${tmp_dir}/display-capture-smoke.mjs"
capture_log="${tmp_dir}/display-capture.log"
base_url="http://127.0.0.1:${port}"
page_url="${base_url}/browser/xbox-boot/"

python3 "${repo_root}/scripts/serve-xbox-browser-boot.py" --port "${port}" >"${server_log}" 2>&1 &
server_pid="$!"

for _ in $(seq 1 50); do
    if curl -fsSI "${page_url}" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
        printf 'BROWSER_DISPLAY_CAPTURE_SMOKE result=fail reason=server-exited log=%s\n' "${server_log}" >&2
        cat "${server_log}" >&2
        exit 1
    fi
    sleep 0.1
done

if ! curl -fsSI "${page_url}" >/dev/null 2>&1; then
    printf 'BROWSER_DISPLAY_CAPTURE_SMOKE result=fail reason=server-not-ready log=%s\n' "${server_log}" >&2
    cat "${server_log}" >&2
    exit 1
fi

cat >"${capture_script}" <<'EOF'
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const pageUrl = process.env.XEMU_BROWSER_DISPLAY_CAPTURE_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_DISPLAY_CAPTURE_TIMEOUT || "15000");
const browserChannel = process.env.XEMU_BROWSER_RUNTIME_CHANNEL || "";
const captureLog = process.env.XEMU_BROWSER_DISPLAY_CAPTURE_LOG;

function fail(reason, detail = "") {
  console.error(`BROWSER_DISPLAY_CAPTURE_SMOKE result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
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
  await page.waitForSelector("#displayCanvas");
  await page.waitForFunction(() => typeof globalThis.xemuBrowserDisplayCapture === "function");

  const first = await page.evaluate(() => globalThis.xemuBrowserDisplayCapture());
  const second = await page.evaluate(() => globalThis.xemuBrowserDisplayCapture({ log: false }));
  if (!first.nonempty || !second.nonempty) {
    fail("empty-canvas");
  }
  if (first.hash !== second.hash) {
    fail("unstable-hash", `first=${first.hash} second=${second.hash}`);
  }
  const transcript = await page.locator("#logOutput").textContent();
  if (!transcript.includes("BOOT_MARK b4 display=visible source=synthetic-framebuffer")) {
    fail("missing-b4-marker");
  }
  if (!transcript.includes("BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes")) {
    fail("missing-capture-marker");
  }

  writeFileSync(captureLog, `${first.marker}\n${first.capture}\n`);
  console.log([
    "BROWSER_DISPLAY_CAPTURE_SMOKE",
    "result=pass",
    "source=synthetic-framebuffer",
    `hash=${first.hash}`,
    `width=${first.width}`,
    `height=${first.height}`,
    `log=${captureLog}`,
  ].join(" "));
} finally {
  await browser.close();
}
EOF

capture_driver_script="${capture_script}"
if ! "${node_bin}" -e 'require.resolve("playwright")' >/dev/null 2>&1; then
    capture_driver_script="${repo_root}/scripts/xbox-browser-display-capture-firefox-bidi.mjs"
fi

XEMU_BROWSER_DISPLAY_CAPTURE_PAGE_URL="${page_url}" \
XEMU_BROWSER_DISPLAY_CAPTURE_TIMEOUT="${timeout_ms}" \
XEMU_BROWSER_RUNTIME_CHANNEL="${browser_channel}" \
XEMU_BROWSER_DISPLAY_CAPTURE_LOG="${capture_log}" \
    "${node_bin}" "${capture_driver_script}"

XEMU_DISPLAY_EVIDENCE_ALLOW_SYNTHETIC=1 \
    "${repo_root}/scripts/xbox-display-capture-evidence-check.sh" "${capture_log}"
