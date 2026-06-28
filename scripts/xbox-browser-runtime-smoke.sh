#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-runtime-smoke.sh

Starts the isolated browser boot server, opens the shell in Playwright Chromium,
checks browser capability UI state, starts either the no-private-assets
synthetic run or a real selected-assets run, and waits for transcript evidence
from the real page/worker path.

Controls:
  XEMU_BROWSER_RUNTIME_PORT       Local server port. Default: 8780.
  XEMU_BROWSER_RUNTIME_TIMEOUT_MS Page/run timeout. Default: 15000.
  XEMU_BROWSER_RUNTIME_BOOT_MS    Browser boot timeout field. Default: 1000.
  XEMU_BROWSER_RUNTIME_BUILD_DIR  Build dir field. Default: ../../build-wasm-pic.
  XEMU_BROWSER_RUNTIME_CHANNEL    Playwright browser channel. Default: auto.
  XEMU_BROWSER_RUNTIME_MODE       synthetic or real. Default: synthetic.
  XEMU_BROWSER_RUNTIME_EXPECT_B3  In real mode, require browser-block B3 read. Default: 1.
  XEMU_BROWSER_RUNTIME_FIXTURE_DIR
                                  Optional fixture dir for auto-discovery.
  XEMU_FLASH, XEMU_HDD            Required in real mode unless auto-discovered.
  XEMU_MCPX, XEMU_EEPROM, XEMU_DVD
                                  Optional real mode assets.
  NODE_BIN                        Node executable override.
  NODE_PATH                       Extra Node module lookup path.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
port="${XEMU_BROWSER_RUNTIME_PORT:-8780}"
timeout_ms="${XEMU_BROWSER_RUNTIME_TIMEOUT_MS:-15000}"
boot_ms="${XEMU_BROWSER_RUNTIME_BOOT_MS:-1000}"
build_dir="${XEMU_BROWSER_RUNTIME_BUILD_DIR:-../../build-wasm-pic}"
browser_channel="${XEMU_BROWSER_RUNTIME_CHANNEL:-}"
runtime_mode="${XEMU_BROWSER_RUNTIME_MODE:-synthetic}"
expect_b3="${XEMU_BROWSER_RUNTIME_EXPECT_B3:-1}"
fixture_dir="${XEMU_BROWSER_RUNTIME_FIXTURE_DIR:-}"
node_bin="${NODE_BIN:-node}"

case "${runtime_mode}" in
    synthetic|real) ;;
    *)
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=bad-mode mode=%s\n' "${runtime_mode}" >&2
        exit 2
        ;;
esac

autodetect_fixture() {
    local env_name="$1"
    local file_name="$2"
    local candidate_dir
    local candidate_path

    if [ -n "${!env_name:-}" ]; then
        return
    fi

    for candidate_dir in \
        "${fixture_dir}" \
        "${repo_root}/fixtures" \
        "${repo_root}/xemu-fixtures"
    do
        if [ -z "${candidate_dir}" ]; then
            continue
        fi
        candidate_path="${candidate_dir}/${file_name}"
        if [ -f "${candidate_path}" ]; then
            export "${env_name}=${candidate_path}"
            printf 'BROWSER_RUNTIME_AUTODETECT name=%s path=%s\n' "${env_name}" "${candidate_path}" >&2
            return
        fi
    done
}

require_file() {
    local name="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=missing-env name=%s\n' "${name}" >&2
        exit 2
    fi
    if [ ! -f "${path}" ]; then
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=missing-file name=%s path=%s\n' "${name}" "${path}" >&2
        exit 2
    fi
}

if [ "${runtime_mode}" = "real" ]; then
    fixture_check_output=""
    fixture_check_status=0

    autodetect_fixture XEMU_FLASH flash.bin
    autodetect_fixture XEMU_HDD xbox_hdd.img
    autodetect_fixture XEMU_MCPX mcpx.bin
    autodetect_fixture XEMU_EEPROM eeprom.bin
    autodetect_fixture XEMU_DVD dvd.iso

    require_file XEMU_FLASH "${XEMU_FLASH:-}"
    require_file XEMU_HDD "${XEMU_HDD:-}"
    set +e
    fixture_check_output="$("${repo_root}/scripts/xbox-boot-fixtures-check.sh" 2>&1)"
    fixture_check_status="$?"
    set -e
    printf '%s\n' "${fixture_check_output}"
    if [ "${fixture_check_status}" -ne 0 ]; then
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=fixture-preflight status=%s\n' \
            "${fixture_check_status}" >&2
        exit "${fixture_check_status}"
    fi
fi

codex_node="/Users/samuelalaniz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
codex_modules="/Users/samuelalaniz/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules"
if [ "${node_bin}" = "node" ] && [ -x "${codex_node}" ]; then
    node_bin="${codex_node}"
fi
if [ -d "${codex_modules}" ]; then
    export NODE_PATH="${codex_modules}${NODE_PATH:+:${NODE_PATH}}"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-browser-runtime-smoke.XXXXXX")"
trap 'rm -rf "${tmp_dir}"; if [ -n "${server_pid:-}" ]; then kill "${server_pid}" >/dev/null 2>&1 || true; wait "${server_pid}" >/dev/null 2>&1 || true; fi' EXIT

server_log="${tmp_dir}/server.log"
runtime_script="${tmp_dir}/runtime-smoke.mjs"
base_url="http://127.0.0.1:${port}"
page_url="${base_url}/browser/xbox-boot/"

python3 "${repo_root}/scripts/serve-xbox-browser-boot.py" --port "${port}" >"${server_log}" 2>&1 &
server_pid="$!"

for _ in $(seq 1 50); do
    if curl -fsSI "${page_url}" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=server-exited log=%s\n' "${server_log}" >&2
        cat "${server_log}" >&2
        exit 1
    fi
    sleep 0.1
done

if ! curl -fsSI "${page_url}" >/dev/null 2>&1; then
    printf 'BROWSER_RUNTIME_SMOKE result=fail reason=server-not-ready log=%s\n' "${server_log}" >&2
    cat "${server_log}" >&2
    exit 1
fi

cat >"${runtime_script}" <<'EOF'
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const pageUrl = process.env.XEMU_BROWSER_RUNTIME_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_RUNTIME_TIMEOUT_MS || "15000");
const bootMs = process.env.XEMU_BROWSER_RUNTIME_BOOT_MS || "1000";
const buildDir = process.env.XEMU_BROWSER_RUNTIME_BUILD_DIR || "../../build-wasm-pic";
const browserChannel = process.env.XEMU_BROWSER_RUNTIME_CHANNEL || "";
const runtimeMode = process.env.XEMU_BROWSER_RUNTIME_MODE || "synthetic";
const expectB3 = process.env.XEMU_BROWSER_RUNTIME_EXPECT_B3 !== "0";
const assetPaths = {
  flash: process.env.XEMU_FLASH || "",
  mcpx: process.env.XEMU_MCPX || "",
  eeprom: process.env.XEMU_EEPROM || "",
  hdd: process.env.XEMU_HDD || "",
  dvd: process.env.XEMU_DVD || "",
};

function fail(reason, detail = "") {
  console.error(`BROWSER_RUNTIME_SMOKE result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
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
  await page.waitForSelector("#capabilities .status-pill");

  const capabilities = await page.locator("#capabilities .status-pill").evaluateAll((nodes) => {
    return nodes.map((node) => {
      const spans = Array.from(node.querySelectorAll("span")).map((span) => span.textContent || "");
      return { name: spans[0] || "", value: spans[1] || "" };
    });
  });
  const required = ["crossOriginIsolated", "SharedArrayBuffer", "Worker", "BigInt", "WebAssembly"];
  for (const name of required) {
    const row = capabilities.find((capability) => capability.name === name);
    if (!row || row.value !== "yes") {
      fail("capability-unavailable", `capability=${name}`);
    }
  }

  const desiredRequireHdd = runtimeMode === "real";
  await page.fill("#timeoutInput", bootMs);
  await page.locator("#timeoutInput").dispatchEvent("change");
  await page.fill("#buildDirInput", buildDir);
  await page.locator("#buildDirInput").dispatchEvent("change");
  if (desiredRequireHdd) {
    await page.check("#requireHddInput");
  } else {
    await page.uncheck("#requireHddInput");
  }
  await page.locator("#requireHddInput").dispatchEvent("change");

  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForSelector("#capabilities .status-pill");
  const persistedConfig = await page.evaluate(() => ({
    timeoutMs: document.querySelector("#timeoutInput")?.value || "",
    buildDir: document.querySelector("#buildDirInput")?.value || "",
    requireHdd: document.querySelector("#requireHddInput")?.checked === true,
  }));
  if (persistedConfig.timeoutMs !== String(bootMs) ||
      persistedConfig.buildDir !== buildDir ||
      persistedConfig.requireHdd !== desiredRequireHdd) {
    fail("config-persist", `expected_timeout=${bootMs} actual_timeout=${persistedConfig.timeoutMs} expected_require_hdd=${desiredRequireHdd ? "yes" : "no"} actual_require_hdd=${persistedConfig.requireHdd ? "yes" : "no"}`);
  }

  await page.fill("#timeoutInput", bootMs);
  await page.fill("#buildDirInput", buildDir);
  if (runtimeMode === "real") {
    await page.setInputFiles("#flashInput", assetPaths.flash);
    if (assetPaths.mcpx) {
      await page.setInputFiles("#mcpxInput", assetPaths.mcpx);
    }
    if (assetPaths.eeprom) {
      await page.setInputFiles("#eepromInput", assetPaths.eeprom);
    }
    await page.setInputFiles("#hddInput", assetPaths.hdd);
    if (assetPaths.dvd) {
      await page.setInputFiles("#dvdInput", assetPaths.dvd);
    }
    await page.check("#requireHddInput");
    await page.click("#startBtn");
  } else {
    await page.click("#syntheticBtn");
  }

  try {
    await page.waitForFunction(() => {
      const text = document.querySelector("#logOutput")?.textContent || "";
      const modeOk = text.includes("BROWSER_RUN_MODE mode=synthetic-zero-flash") ||
        text.includes("BROWSER_RUN_MODE mode=selected-assets");
      return modeOk &&
        text.includes("BROWSER_CAPABILITY name=SharedArrayBuffer available=yes") &&
        text.includes("BROWSER_ARTIFACT kind=js") &&
        text.includes("BROWSER_ARTIFACT kind=wasm") &&
        text.includes("BROWSER_ASSET_VALIDATE result=pass") &&
        text.includes("BROWSER_BOOT_RESULT result=");
    }, null, { timeout: timeoutMs });
  } catch (error) {
    const transcript = await page.locator("#logOutput").textContent().catch(() => "");
    console.error("BROWSER_RUNTIME_TRANSCRIPT_BEGIN");
    console.error(transcript || "");
    console.error("BROWSER_RUNTIME_TRANSCRIPT_END");
    throw error;
  }

  const transcript = await page.locator("#logOutput").textContent();
  const resultMatch = transcript.match(/BROWSER_BOOT_RESULT result=([^\s]+)/);
  if (!resultMatch) {
    fail("missing-boot-result");
  }
  const transcriptLines = transcript.split(/\r?\n/).filter((line) => line.length > 0);
  const b3Source = transcript.includes("BOOT_MARK b3 browser_block=read")
    ? "browser-block"
    : transcript.includes("BOOT_MARK b3 ide=hdd")
      ? "ide-hdd"
      : runtimeMode === "real" && expectB3
        ? "missing"
        : "not-required";
  const hddAsset = transcript.includes("BROWSER_ASSET name=hdd");
  if (runtimeMode === "real") {
    if (!transcript.includes("BROWSER_RUN_MODE mode=selected-assets")) {
      fail("missing-real-run-mode");
    }
    if (!hddAsset) {
      fail("missing-hdd-asset");
    }
    if (expectB3 && b3Source === "missing") {
      fail("missing-b3-marker");
    }
  }

  console.log([
    "BROWSER_RUNTIME_TRANSCRIPT",
    "result=pass",
    `mode=${runtimeMode}`,
    `lines=${transcriptLines.length}`,
    `run_mode=${runtimeMode === "real" ? "selected-assets" : "synthetic-zero-flash"}`,
    `hdd_asset=${hddAsset ? "yes" : "no"}`,
    `b3_marker=${b3Source === "missing" ? "missing" : b3Source}`,
    "capability_sab=yes",
    "artifact_js=yes",
    "artifact_wasm=yes",
    "asset_validate=yes",
    "config_persist=yes",
  ].join(" "));

  console.log([
    "BROWSER_RUNTIME_SMOKE",
    "result=pass",
    `url=${JSON.stringify(pageUrl)}`,
    "capabilities=yes",
    `mode=${runtimeMode}`,
    "artifacts=yes",
    "asset_validate=yes",
    "config_persist=yes",
    `b3=${runtimeMode === "real" && expectB3 ? "required" : "not-required"}`,
    `boot_result=${resultMatch[1]}`,
  ].join(" "));
} finally {
  await browser.close();
}
EOF

XEMU_BROWSER_RUNTIME_PAGE_URL="${page_url}" \
XEMU_BROWSER_RUNTIME_TIMEOUT_MS="${timeout_ms}" \
XEMU_BROWSER_RUNTIME_BOOT_MS="${boot_ms}" \
XEMU_BROWSER_RUNTIME_BUILD_DIR="${build_dir}" \
XEMU_BROWSER_RUNTIME_CHANNEL="${browser_channel}" \
XEMU_BROWSER_RUNTIME_MODE="${runtime_mode}" \
XEMU_BROWSER_RUNTIME_EXPECT_B3="${expect_b3}" \
XEMU_FLASH="${XEMU_FLASH:-}" \
XEMU_MCPX="${XEMU_MCPX:-}" \
XEMU_EEPROM="${XEMU_EEPROM:-}" \
XEMU_HDD="${XEMU_HDD:-}" \
XEMU_DVD="${XEMU_DVD:-}" \
    "${node_bin}" "${runtime_script}"
