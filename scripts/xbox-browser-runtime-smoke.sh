#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-runtime-smoke.sh

Starts the isolated browser boot server, opens the shell in Playwright,
checks browser capability UI state, starts either the no-private-assets
synthetic run or a real selected-assets run, and waits for transcript evidence
from the real page/worker path.

Controls:
  XEMU_BROWSER_RUNTIME_PORT       Local server port. Default: 8780.
  XEMU_BROWSER_RUNTIME_TIMEOUT_MS Page/run timeout. Default: 15000.
  XEMU_BROWSER_RUNTIME_BOOT_MS    Browser boot timeout field. Default: 1000.
  XEMU_BROWSER_RUNTIME_BUILD_DIR  Build dir field. Default: ../../build-wasm-pic.
  XEMU_BROWSER_RUNTIME_BROWSER    Playwright browser: chromium or firefox. Default: chromium.
  XEMU_BROWSER_RUNTIME_PLAYWRIGHT_BROWSER
                                  Alias for XEMU_BROWSER_RUNTIME_BROWSER.
  XEMU_BROWSER_RUNTIME_CHANNEL    Playwright browser channel. Default: auto.
                                  Applies to Chromium only.
  XEMU_BROWSER_RUNTIME_DRIVER     auto, playwright, or firefox-bidi.
                                  Default: auto. firefox-bidi requires
                                  XEMU_BROWSER_RUNTIME_BROWSER=firefox.
  XEMU_BROWSER_RUNTIME_MODE       synthetic or real. Default: synthetic.
  XEMU_BROWSER_RUNTIME_EXPECT_B3  In real mode, require browser-block B3 read. Default: 1.
  XEMU_BROWSER_RUNTIME_FIXTURE_DIR
                                  Optional fixture dir for auto-discovery.
  XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE
                                  Optional browser-only B6 diagnostic:
                                  normal, off,
                                  suppress-until-dashboard-observed, or
                                  suppress-until-entry-ready.
  XEMU_BROWSER_BOOT_ICOUNT        Optional browser-only B6 timing diagnostic
                                  passed as QEMU -icount value, for example
                                  shift=10,sleep=off.
  XEMU_BROWSER_DASHBOARD_NATIVE_HASH
                                  Optional native reference frame hash. When
                                  set, the browser runtime emits
                                  BROWSER_DASHBOARD_CAPTURE evidence from the
                                  latest non-empty browser display capture.
  XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED
                                  Require dashboard=xbe-executed before
                                  BROWSER_DASHBOARD_CAPTURE can pass. Default:
                                  1.
  XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT
                                  Optional B6 browser PIC IRQ trace limit.
  XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT
                                  Optional B6 browser CPU hard-IRQ trace limit.
  XEMU_BOOT_TRACE_XBE_IRET_LIMIT
                                  Optional B6 browser protected-mode IRET trace limit.
  XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT
                                  Optional B6 browser PIT IRQ timer trace limit.
  XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT
                                  Optional B6 browser main-loop timer trace limit.
  XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT
                                  Optional B6 browser-headless host timer pump
                                  progress cap. Diagnostic only; default is
                                  unlimited.
  XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE
                                  Optional B6 browser-headless host timer pump
                                  gate mode: default, entry-ready,
                                  after-pfifo-empty, or
                                  pfifo-before-transition-activity, or
                                  pfifo-before-transition-activity-then-after-pfifo-empty.
                                  Diagnostic only; default preserves current
                                  XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY
                                  behavior.
  XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT
                                  Optional B6 browser kernel-loop trace limit.
  XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT
                                  Optional B6 browser kernel-loop trace limit
                                  after PFIFO reaches pusher-empty.
  XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS
                                  Optional B6 browser kernel-loop repeated-edge
                                  threshold.
  XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS
                                  Optional B6 low-RAM physical word watch,
                                  for example 0x0003a890. Diagnostic only.
  XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT
                                  Optional B6 memory-watch sample/access limit.
  XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS
                                  Optional B6 memory-watch callback access
                                  filter: all/read/write, or off. Default
                                  leaves only cheap sampled fields.
  XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL
                                  Optional B6 browser TCG timer pump interval,
                                  in translated blocks. Default: disabled.
  XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT
                                  Optional B6 browser after-idle sample
                                  threshold before pit-after-idle-full pumping.
  XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE
                                  Optional B6 browser TCG timer pump mode:
                                  all, idle-loop, idle-loop-serviceable,
                                  idle-loop-serviceable-pit-only,
                                  pit-after-idle, pit-after-idle-full,
                                  pit-after-pfifo-transition,
                                  pit-before-pfifo-transition,
                                  pit-before-pfifo-transition-activity,
                                  pit-before-pfifo-transition-activity-defer,
                                  pit-before-pfifo-transition-activity-pre-tb-defer,
                                  pit-before-pfifo-transition-activity-defer-to-idle,
                                  or pit-at-pfifo-transition-pre-commit-defer-to-idle.
                                  Default: all.
  XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT
                                  Optional B6 browser CPU idle-before-PFIFO
                                  transition trace limit.
  XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY
                                  Set to 1 to log B6 PIC/CPU IRQ markers only
                                  after PFIFO reaches pusher-empty.
  XEMU_BOOT_TRACE_XBE_IRQ_WATCH   Optional comma-separated PIC IRQs whose
                                  B6 PIC/LPC markers bypass the PFIFO-empty
                                  logging gate.
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
playwright_browser="${XEMU_BROWSER_RUNTIME_BROWSER:-${XEMU_BROWSER_RUNTIME_PLAYWRIGHT_BROWSER:-chromium}}"
browser_channel="${XEMU_BROWSER_RUNTIME_CHANNEL:-}"
runtime_driver="${XEMU_BROWSER_RUNTIME_DRIVER:-auto}"
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

case "${playwright_browser}" in
    chromium|firefox) ;;
    *)
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=bad-playwright-browser browser=%s\n' \
            "${playwright_browser}" >&2
        exit 2
        ;;
esac

case "${runtime_driver}" in
    auto|playwright|firefox-bidi) ;;
    *)
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=bad-runtime-driver driver=%s\n' \
            "${runtime_driver}" >&2
        exit 2
        ;;
esac

if [ "${runtime_driver}" = "firefox-bidi" ] && [ "${playwright_browser}" != "firefox" ]; then
    printf 'BROWSER_RUNTIME_SMOKE result=fail reason=firefox-bidi-requires-firefox browser=%s\n' \
        "${playwright_browser}" >&2
    exit 2
fi

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
const playwright = require("playwright");

const pageUrl = process.env.XEMU_BROWSER_RUNTIME_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_RUNTIME_TIMEOUT_MS || "15000");
const bootMs = process.env.XEMU_BROWSER_RUNTIME_BOOT_MS || "1000";
const buildDir = process.env.XEMU_BROWSER_RUNTIME_BUILD_DIR || "../../build-wasm-pic";
const browserName = process.env.XEMU_BROWSER_RUNTIME_BROWSER || "chromium";
const browserChannel = process.env.XEMU_BROWSER_RUNTIME_CHANNEL || "";
const runtimeMode = process.env.XEMU_BROWSER_RUNTIME_MODE || "synthetic";
const expectB3 = process.env.XEMU_BROWSER_RUNTIME_EXPECT_B3 !== "0";
const dumpTranscript = process.env.XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT === "1";
const pcrtcVblankMode = process.env.XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE || "";
const browserIcount = process.env.XEMU_BROWSER_BOOT_ICOUNT || "";
const dashboardNativeHash = process.env.XEMU_BROWSER_DASHBOARD_NATIVE_HASH || "";
const dashboardCaptureRequireExecuted =
  process.env.XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED !== "0";
const traceOptions = {
  xbeExecProbeLimit: process.env.XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT || "",
  xbeExecProbeStride: process.env.XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE || "",
  xbePhysCompareLimit: process.env.XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT || "",
  xbePicIrqLimit: process.env.XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT || "",
  xbeCpuHardIrqLimit: process.env.XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT || "",
  xbeIretLimit: process.env.XEMU_BOOT_TRACE_XBE_IRET_LIMIT || "",
  xbePitIrqLimit: process.env.XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT || "",
  xbeMainLoopTimerLimit: process.env.XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT || "",
  browserHeadlessTimerPumpProgressLimit:
    process.env.XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT || "",
  browserHeadlessTimerPumpMode:
    process.env.XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE || "",
  xbeKernelLoopLimit: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT || "",
  xbeKernelLoopAfterIdleLimit: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT || "",
  xbeKernelLoopMinHits: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS || "",
  xbeMemoryWatchPhys: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS || "",
  xbeMemoryWatchLimit: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT || "",
  xbeMemoryWatchAccess: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS || "",
  xbeTcgTimerPumpInterval: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL || "",
  xbeTcgTimerPumpAfterIdleLimit: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT || "",
  xbeTcgTimerPumpMode: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE || "",
  xbeIdleBeforePfifoTransitionLimit: process.env.XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT || "",
  xbeIrqAfterPfifoEmptyOnly: process.env.XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY || "",
  xbeIrqWatch: process.env.XEMU_BOOT_TRACE_XBE_IRQ_WATCH || "",
};
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

function emitDisplayEvidence(transcript) {
  for (const line of transcript.split(/\r?\n/)) {
    if (line.startsWith("BOOT_MARK b4 ") ||
        line.startsWith("BROWSER_DISPLAY_CAPTURE ")) {
      console.log(line);
    }
  }
}

function lineValue(line, key, defaultValue = "") {
  const prefix = `${key}=`;
  for (const token of line.split(/\s+/)) {
    if (token.startsWith(prefix)) {
      return token.slice(prefix.length).replace(/^"|"$/g, "");
    }
  }
  return defaultValue;
}

function emitDashboardCaptureEvidence(transcript) {
  if (!dashboardNativeHash) {
    return;
  }

  const lines = transcript.split(/\r?\n/);
  const executed = lines.some((line) =>
    line.startsWith("BOOT_MARK b6 dashboard=xbe-executed ") &&
    line.includes(" context=browser-runtime ")
  );
  if (dashboardCaptureRequireExecuted && !executed) {
    console.log([
      "BROWSER_DASHBOARD_CAPTURE",
      "result=skip",
      "reason=missing-xbe-executed",
      "native_ref_match=no",
      "hash=missing",
      `native_hash=${dashboardNativeHash}`,
      "source=browser-framebuffer",
      "width=0",
      "height=0",
    ].join(" "));
    return;
  }

  const captureLine = lines.filter((line) =>
    line.startsWith("BROWSER_DISPLAY_CAPTURE ") &&
    lineValue(line, "result") === "pass" &&
    lineValue(line, "nonempty") === "yes"
  ).pop();
  if (!captureLine) {
    console.log([
      "BROWSER_DASHBOARD_CAPTURE",
      "result=fail",
      "reason=missing-display-capture",
      "native_ref_match=no",
      "hash=missing",
      `native_hash=${dashboardNativeHash}`,
      "source=browser-framebuffer",
      "width=0",
      "height=0",
    ].join(" "));
    return;
  }

  const hash = lineValue(captureLine, "hash", "missing");
  const source = lineValue(captureLine, "source", "browser-framebuffer");
  const width = lineValue(captureLine, "width", "0");
  const height = lineValue(captureLine, "height", "0");
  const nativeRefMatch =
    hash.toLowerCase() === dashboardNativeHash.toLowerCase();
  console.log([
    "BROWSER_DASHBOARD_CAPTURE",
    `result=${nativeRefMatch ? "pass" : "fail"}`,
    `native_ref_match=${nativeRefMatch ? "yes" : "no"}`,
    `hash=${hash}`,
    `native_hash=${dashboardNativeHash}`,
    `source=${source}`,
    `width=${width}`,
    `height=${height}`,
  ].join(" "));
}

const launchOptions = {
  headless: true,
};
if (browserName !== "chromium" && browserName !== "firefox") {
  fail("bad-playwright-browser", `browser=${browserName}`);
}
const browserType = playwright[browserName];
if (!browserType) {
  fail("missing-playwright-browser", `browser=${browserName}`);
}
if (browserName === "chromium") {
  launchOptions.args = ["--no-sandbox"];
}
if (browserChannel && browserName === "chromium") {
  launchOptions.channel = browserChannel;
} else if (!browserChannel && browserName === "chromium" && process.platform === "darwin") {
  const { existsSync } = require("node:fs");
  if (existsSync("/Applications/Google Chrome.app")) {
    launchOptions.channel = "chrome";
  }
} else if (browserChannel) {
  console.log(`BROWSER_RUNTIME_PLAYWRIGHT_CHANNEL ignored=yes browser=${browserName} channel=${browserChannel}`);
}

console.log([
  "BROWSER_RUNTIME_PLAYWRIGHT",
  `browser=${browserName}`,
  `channel=${launchOptions.channel || "default"}`,
].join(" "));

const browser = await browserType.launch(launchOptions);

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
  await page.evaluate(({ pcrtcVblankMode, browserIcount, traceOptions }) => {
    globalThis.xemuBrowserBootPcrtcVblankMode = pcrtcVblankMode;
    globalThis.xemuBrowserBootIcount = browserIcount;
    globalThis.xemuBrowserBootTraceOptions = traceOptions;
  }, { pcrtcVblankMode, browserIcount, traceOptions });
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
  const b4Marker = transcript.includes("BOOT_MARK b4 display=visible");
  const displayCapture = transcript.includes("BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes");
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

  if (dumpTranscript) {
    console.log("BROWSER_RUNTIME_TRANSCRIPT_BEGIN");
    console.log(transcript.trimEnd());
    console.log("BROWSER_RUNTIME_TRANSCRIPT_END");
  }

  emitDisplayEvidence(transcript);
  emitDashboardCaptureEvidence(transcript);

  console.log([
    "BROWSER_RUNTIME_TRANSCRIPT",
    "result=pass",
    `mode=${runtimeMode}`,
    `browser=${browserName}`,
    `lines=${transcriptLines.length}`,
    `run_mode=${runtimeMode === "real" ? "selected-assets" : "synthetic-zero-flash"}`,
    `hdd_asset=${hddAsset ? "yes" : "no"}`,
    `b3_marker=${b3Source === "missing" ? "missing" : b3Source}`,
    "capability_sab=yes",
    "artifact_js=yes",
    "artifact_wasm=yes",
    "asset_validate=yes",
    "config_persist=yes",
    `pcrtc_vblank_mode=${pcrtcVblankMode || "normal"}`,
    `browser_icount=${browserIcount || "off"}`,
    `trace_xbe_exec_probe_limit=${traceOptions.xbeExecProbeLimit || "default"}`,
    `trace_xbe_exec_probe_stride=${traceOptions.xbeExecProbeStride || "default"}`,
    `trace_xbe_phys_compare_limit=${traceOptions.xbePhysCompareLimit || "default"}`,
    `trace_xbe_pic_irq_limit=${traceOptions.xbePicIrqLimit || "default"}`,
    `trace_xbe_cpu_hard_irq_limit=${traceOptions.xbeCpuHardIrqLimit || "default"}`,
    `trace_xbe_iret_limit=${traceOptions.xbeIretLimit || "default"}`,
    `trace_xbe_pit_irq_limit=${traceOptions.xbePitIrqLimit || "default"}`,
    `trace_xbe_main_loop_timer_limit=${traceOptions.xbeMainLoopTimerLimit || "default"}`,
    `browser_headless_timer_pump_progress_limit=${traceOptions.browserHeadlessTimerPumpProgressLimit || "default"}`,
    `browser_headless_timer_pump_mode=${traceOptions.browserHeadlessTimerPumpMode || "default"}`,
    `trace_xbe_kernel_loop_limit=${traceOptions.xbeKernelLoopLimit || "default"}`,
    `trace_xbe_kernel_loop_after_idle_limit=${traceOptions.xbeKernelLoopAfterIdleLimit || "default"}`,
    `trace_xbe_kernel_loop_min_hits=${traceOptions.xbeKernelLoopMinHits || "default"}`,
    `trace_xbe_memory_watch_phys=${traceOptions.xbeMemoryWatchPhys || "default"}`,
    `trace_xbe_memory_watch_limit=${traceOptions.xbeMemoryWatchLimit || "default"}`,
    `trace_xbe_memory_watch_access=${traceOptions.xbeMemoryWatchAccess || "default"}`,
    `trace_xbe_tcg_timer_pump_interval=${traceOptions.xbeTcgTimerPumpInterval || "default"}`,
    `trace_xbe_tcg_timer_pump_after_idle_limit=${traceOptions.xbeTcgTimerPumpAfterIdleLimit || "default"}`,
    `trace_xbe_tcg_timer_pump_mode=${traceOptions.xbeTcgTimerPumpMode || "default"}`,
    `trace_xbe_idle_before_pfifo_transition_limit=${traceOptions.xbeIdleBeforePfifoTransitionLimit || "default"}`,
    `trace_xbe_irq_after_pfifo_empty_only=${traceOptions.xbeIrqAfterPfifoEmptyOnly || "default"}`,
    `trace_xbe_irq_watch=${traceOptions.xbeIrqWatch || "default"}`,
    `b4_marker=${b4Marker ? "yes" : "no"}`,
    `display_capture=${displayCapture ? "yes" : "no"}`,
  ].join(" "));

  console.log([
    "BROWSER_RUNTIME_SMOKE",
    "result=pass",
    `url=${JSON.stringify(pageUrl)}`,
    "capabilities=yes",
    `mode=${runtimeMode}`,
    `browser=${browserName}`,
    "artifacts=yes",
    "asset_validate=yes",
    "config_persist=yes",
    `pcrtc_vblank_mode=${pcrtcVblankMode || "normal"}`,
    `browser_icount=${browserIcount || "off"}`,
    `trace_xbe_exec_probe_limit=${traceOptions.xbeExecProbeLimit || "default"}`,
    `trace_xbe_exec_probe_stride=${traceOptions.xbeExecProbeStride || "default"}`,
    `trace_xbe_phys_compare_limit=${traceOptions.xbePhysCompareLimit || "default"}`,
    `trace_xbe_pic_irq_limit=${traceOptions.xbePicIrqLimit || "default"}`,
    `trace_xbe_cpu_hard_irq_limit=${traceOptions.xbeCpuHardIrqLimit || "default"}`,
    `trace_xbe_iret_limit=${traceOptions.xbeIretLimit || "default"}`,
    `trace_xbe_pit_irq_limit=${traceOptions.xbePitIrqLimit || "default"}`,
      `trace_xbe_main_loop_timer_limit=${traceOptions.xbeMainLoopTimerLimit || "default"}`,
      `browser_headless_timer_pump_progress_limit=${traceOptions.browserHeadlessTimerPumpProgressLimit || "default"}`,
      `browser_headless_timer_pump_mode=${traceOptions.browserHeadlessTimerPumpMode || "default"}`,
      `trace_xbe_kernel_loop_limit=${traceOptions.xbeKernelLoopLimit || "default"}`,
    `trace_xbe_kernel_loop_after_idle_limit=${traceOptions.xbeKernelLoopAfterIdleLimit || "default"}`,
    `trace_xbe_kernel_loop_min_hits=${traceOptions.xbeKernelLoopMinHits || "default"}`,
    `trace_xbe_memory_watch_phys=${traceOptions.xbeMemoryWatchPhys || "default"}`,
    `trace_xbe_memory_watch_limit=${traceOptions.xbeMemoryWatchLimit || "default"}`,
    `trace_xbe_memory_watch_access=${traceOptions.xbeMemoryWatchAccess || "default"}`,
    `trace_xbe_tcg_timer_pump_interval=${traceOptions.xbeTcgTimerPumpInterval || "default"}`,
    `trace_xbe_tcg_timer_pump_after_idle_limit=${traceOptions.xbeTcgTimerPumpAfterIdleLimit || "default"}`,
    `trace_xbe_tcg_timer_pump_mode=${traceOptions.xbeTcgTimerPumpMode || "default"}`,
    `trace_xbe_idle_before_pfifo_transition_limit=${traceOptions.xbeIdleBeforePfifoTransitionLimit || "default"}`,
    `trace_xbe_irq_after_pfifo_empty_only=${traceOptions.xbeIrqAfterPfifoEmptyOnly || "default"}`,
    `trace_xbe_irq_watch=${traceOptions.xbeIrqWatch || "default"}`,
    `b3=${runtimeMode === "real" && expectB3 ? "required" : "not-required"}`,
    `boot_result=${resultMatch[1]}`,
  ].join(" "));
} finally {
  await browser.close();
}
EOF

runtime_driver_script="${runtime_script}"
if [ "${runtime_driver}" = "firefox-bidi" ]; then
    runtime_driver_script="${repo_root}/scripts/xbox-browser-runtime-firefox-bidi.mjs"
elif ! "${node_bin}" -e 'require.resolve("playwright")' >/dev/null 2>&1; then
    if [ "${runtime_driver}" = "playwright" ]; then
        printf 'BROWSER_RUNTIME_SMOKE result=fail reason=missing-playwright\n' >&2
        exit 1
    fi
    runtime_driver_script="${repo_root}/scripts/xbox-browser-runtime-firefox-bidi.mjs"
fi

XEMU_BROWSER_RUNTIME_PAGE_URL="${page_url}" \
XEMU_BROWSER_RUNTIME_TIMEOUT_MS="${timeout_ms}" \
XEMU_BROWSER_RUNTIME_BOOT_MS="${boot_ms}" \
XEMU_BROWSER_RUNTIME_BUILD_DIR="${build_dir}" \
XEMU_BROWSER_RUNTIME_BROWSER="${playwright_browser}" \
XEMU_BROWSER_RUNTIME_DRIVER="${runtime_driver}" \
XEMU_BROWSER_RUNTIME_CHANNEL="${browser_channel}" \
XEMU_BROWSER_RUNTIME_MODE="${runtime_mode}" \
XEMU_BROWSER_RUNTIME_EXPECT_B3="${expect_b3}" \
XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT="${XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT:-0}" \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE="${XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE:-}" \
XEMU_BROWSER_BOOT_ICOUNT="${XEMU_BROWSER_BOOT_ICOUNT:-}" \
XEMU_BROWSER_DASHBOARD_NATIVE_HASH="${XEMU_BROWSER_DASHBOARD_NATIVE_HASH:-}" \
XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED="${XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED:-}" \
XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT="${XEMU_BOOT_TRACE_XBE_EXEC_PROBE_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE="${XEMU_BOOT_TRACE_XBE_EXEC_PROBE_STRIDE:-}" \
XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT="${XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT="${XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT="${XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT="${XEMU_BOOT_TRACE_XBE_IRET_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT="${XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT="${XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT:-}" \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT="${XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT:-}" \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE="${XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE:-}" \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT="${XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT="${XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS="${XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS:-}" \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS="${XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS:-}" \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT="${XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS="${XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS:-}" \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL="${XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL:-}" \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT="${XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE="${XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE:-}" \
XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT="${XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT:-}" \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY="${XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY:-}" \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH="${XEMU_BOOT_TRACE_XBE_IRQ_WATCH:-}" \
XEMU_FLASH="${XEMU_FLASH:-}" \
XEMU_MCPX="${XEMU_MCPX:-}" \
XEMU_EEPROM="${XEMU_EEPROM:-}" \
XEMU_HDD="${XEMU_HDD:-}" \
XEMU_DVD="${XEMU_DVD:-}" \
    "${node_bin}" "${runtime_driver_script}"
