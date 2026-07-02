#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const pageUrl = process.env.XEMU_BROWSER_RUNTIME_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_RUNTIME_TIMEOUT_MS || "15000");
const bootMs = process.env.XEMU_BROWSER_RUNTIME_BOOT_MS || "1000";
const buildDir = process.env.XEMU_BROWSER_RUNTIME_BUILD_DIR || "../../build-wasm-pic";
const runtimeMode = process.env.XEMU_BROWSER_RUNTIME_MODE || "synthetic";
const expectB3 = process.env.XEMU_BROWSER_RUNTIME_EXPECT_B3 !== "0";
const firefoxBin = process.env.XEMU_BROWSER_RUNTIME_FIREFOX_BIN || "firefox";
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
  xbeTimerOpportunityLimit: process.env.XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT || "",
  xbeEdgeDecisionLimit: process.env.XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT || "",
  xbeTickBlockLimit: process.env.XEMU_BOOT_TRACE_XBE_TICK_BLOCK_LIMIT || "",
  xbeTickBlockIrqDefer: process.env.XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER || "",
  xbeTickBlockIrqDeferLimit: process.env.XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER_LIMIT || "",
  browserHeadlessTimerPumpProgressLimit:
    process.env.XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT || "",
  browserHeadlessTimerPumpMode:
    process.env.XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE || "",
  browserBootDeterministic: process.env.XEMU_BROWSER_BOOT_DETERMINISTIC || "",
  browserBootDeterministicTimerSteps:
    process.env.XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS || "",
  browserBootDeterministicWarmupProgressLimit:
    process.env.XEMU_BROWSER_BOOT_DETERMINISTIC_WARMUP_PROGRESS_LIMIT || "",
  browserBootDeterministicPcrtcPrestream:
    process.env.XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM || "",
  xbeKernelLoopLimit: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT || "",
  xbeKernelLoopAfterIdleLimit: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT || "",
  xbeKernelLoopMinHits: process.env.XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS || "",
  xbeMemoryWatchPhys: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS || "",
  xbeMemoryWatchLimit: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT || "",
  xbeMemoryWatchAccess: process.env.XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS || "",
  nv2aUserDmaPutLimit: process.env.XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT || "",
  xbeTcgTimerPumpInterval: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL || "",
  xbeTcgTimerPumpAfterIdleLimit: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT || "",
  xbeTcgTimerPumpMode: process.env.XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE || "",
  xbeIdleBeforePfifoTransitionLimit: process.env.XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT || "",
  xbeIrqAfterPfifoEmptyOnly: process.env.XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY || "",
  xbeIrqWatch: process.env.XEMU_BOOT_TRACE_XBE_IRQ_WATCH || "",
  callChainTrace: process.env.XEMU_BOOT_TRACE_CALL_CHAIN || "",
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

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function findFreePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
    server.on("error", reject);
  });
}

async function waitForTcp(port, child, stderrRef) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error(`firefox-exited exit=${child.exitCode} stderr=${JSON.stringify(stderrRef.text.slice(-2000))}`);
    }
    const connected = await new Promise((resolve) => {
      const socket = net.createConnection({ host: "127.0.0.1", port });
      socket.once("connect", () => {
        socket.destroy();
        resolve(true);
      });
      socket.once("error", () => resolve(false));
      socket.setTimeout(250, () => {
        socket.destroy();
        resolve(false);
      });
    });
    if (connected) {
      return;
    }
    await delay(100);
  }
  throw new Error(`firefox-debug-port-timeout stderr=${JSON.stringify(stderrRef.text.slice(-2000))}`);
}

class BidiClient {
  constructor(ws) {
    this.ws = ws;
    this.nextId = 1;
    this.pending = new Map();
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id && this.pending.has(message.id)) {
        const { resolve, reject } = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.type === "error" || message.error) {
          reject(new Error(JSON.stringify(message)));
        } else {
          resolve(message);
        }
      }
    };
    ws.onclose = () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error("WebDriver BiDi connection closed"));
      }
      this.pending.clear();
    };
  }

  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      ws.onopen = resolve;
      ws.onerror = (event) => reject(new Error(event.message || event.type || "WebSocket error"));
    });
    return new BidiClient(ws);
  }

  async send(method, params = {}) {
    const id = this.nextId++;
    this.ws.send(JSON.stringify({ id, method, params }));
    return await new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  async evaluateJson(context, fn, arg) {
    const expression = `(async () => JSON.stringify(await (${fn.toString()})(${JSON.stringify(arg)})))()`;
    const message = await this.send("script.evaluate", {
      target: { context },
      expression,
      awaitPromise: true,
    });
    const evaluation = message.result;
    if (evaluation.type !== "success") {
      throw new Error(`script-exception ${JSON.stringify(evaluation.exceptionDetails || evaluation)}`);
    }
    const value = evaluation.result && evaluation.result.value;
    if (typeof value !== "string") {
      throw new Error(`script-non-string-result ${JSON.stringify(evaluation.result)}`);
    }
    return JSON.parse(value);
  }

  close() {
    this.ws.close();
  }
}

async function configurePage({ bootMs, buildDir, runtimeMode }) {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const waitFor = async (predicate, timeout, reason) => {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      if (predicate()) {
        return;
      }
      await sleep(50);
    }
    throw new Error(reason);
  };
  await waitFor(() => document.querySelector("#capabilities .status-pill"), 10000, "capabilities-timeout");

  const capabilities = Array.from(document.querySelectorAll("#capabilities .status-pill")).map((node) => {
    const spans = Array.from(node.querySelectorAll("span")).map((span) => span.textContent || "");
    return { name: spans[0] || "", value: spans[1] || "" };
  });
  const required = ["crossOriginIsolated", "SharedArrayBuffer", "Worker", "BigInt", "WebAssembly"];
  for (const name of required) {
    const row = capabilities.find((capability) => capability.name === name);
    if (!row || row.value !== "yes") {
      throw new Error(`capability-unavailable capability=${name}`);
    }
  }

  const desiredRequireHdd = runtimeMode === "real";
  const timeoutInput = document.querySelector("#timeoutInput");
  const buildDirInput = document.querySelector("#buildDirInput");
  const requireHddInput = document.querySelector("#requireHddInput");
  timeoutInput.value = String(bootMs);
  timeoutInput.dispatchEvent(new Event("change", { bubbles: true }));
  buildDirInput.value = buildDir;
  buildDirInput.dispatchEvent(new Event("change", { bubbles: true }));
  requireHddInput.checked = desiredRequireHdd;
  requireHddInput.dispatchEvent(new Event("change", { bubbles: true }));
  return { capabilities };
}

async function runPage({ timeoutMs, bootMs, buildDir, runtimeMode, expectB3, assets, pcrtcVblankMode, browserIcount, traceOptions }) {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const waitFor = async (predicate, timeout, reason) => {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      if (predicate()) {
        return;
      }
      await sleep(100);
    }
    throw new Error(reason);
  };
  const transcriptText = () => document.querySelector("#logOutput")?.textContent || "";
  const dispatchChange = (element) => element.dispatchEvent(new Event("change", { bubbles: true }));
  const setValue = (selector, value) => {
    const element = document.querySelector(selector);
    element.value = value;
    dispatchChange(element);
  };
  const setChecked = (selector, checked) => {
    const element = document.querySelector(selector);
    element.checked = checked;
    dispatchChange(element);
  };
  const smokeAssetFile = async (key) => {
    const response = await fetch(`/__xemu_smoke_asset/${key}`, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`asset-fetch-failed key=${key} status=${response.status}`);
    }
    const buffer = await response.arrayBuffer();
    const filename = response.headers.get("X-Xemu-Asset-Filename") || `${key}.bin`;
    return new File([buffer], filename, { type: "application/octet-stream" });
  };
  const setFile = async (selector, key) => {
    const input = document.querySelector(selector);
    const file = await smokeAssetFile(key);
    const transfer = new DataTransfer();
    transfer.items.add(file);
    input.files = transfer.files;
    dispatchChange(input);
  };

  try {
    await waitFor(() => document.querySelector("#capabilities .status-pill"), 10000, "capabilities-timeout");
    const desiredRequireHdd = runtimeMode === "real";
    const persistedConfig = {
      timeoutMs: document.querySelector("#timeoutInput")?.value || "",
      buildDir: document.querySelector("#buildDirInput")?.value || "",
      requireHdd: document.querySelector("#requireHddInput")?.checked === true,
    };
    if (persistedConfig.timeoutMs !== String(bootMs) ||
        persistedConfig.buildDir !== buildDir ||
        persistedConfig.requireHdd !== desiredRequireHdd) {
      throw new Error(`config-persist expected_timeout=${bootMs} actual_timeout=${persistedConfig.timeoutMs} expected_require_hdd=${desiredRequireHdd ? "yes" : "no"} actual_require_hdd=${persistedConfig.requireHdd ? "yes" : "no"}`);
    }

    setValue("#timeoutInput", String(bootMs));
    setValue("#buildDirInput", buildDir);
    setChecked("#requireHddInput", desiredRequireHdd);
    globalThis.xemuBrowserBootPcrtcVblankMode = pcrtcVblankMode || "";
    globalThis.xemuBrowserBootIcount = browserIcount || "";
    globalThis.xemuBrowserBootTraceOptions = traceOptions || {};

    if (runtimeMode === "real") {
      await setFile("#flashInput", "flash");
      if (assets.mcpx) {
        await setFile("#mcpxInput", "mcpx");
      }
      if (assets.eeprom) {
        await setFile("#eepromInput", "eeprom");
      }
      await setFile("#hddInput", "hdd");
      if (assets.dvd) {
        await setFile("#dvdInput", "dvd");
      }
      setChecked("#requireHddInput", true);
      document.querySelector("#startBtn").click();
    } else {
      document.querySelector("#syntheticBtn").click();
    }

    await waitFor(() => {
      const text = transcriptText();
      const modeOk = text.includes("BROWSER_RUN_MODE mode=synthetic-zero-flash") ||
        text.includes("BROWSER_RUN_MODE mode=selected-assets");
      return modeOk &&
        text.includes("BROWSER_CAPABILITY name=SharedArrayBuffer available=yes") &&
        text.includes("BROWSER_ARTIFACT kind=js") &&
        text.includes("BROWSER_ARTIFACT kind=wasm") &&
        text.includes("BROWSER_ASSET_VALIDATE result=pass") &&
        text.includes("BROWSER_BOOT_RESULT result=");
    }, timeoutMs, "runtime-timeout");

    const transcript = transcriptText();
    if (runtimeMode === "real") {
      if (!transcript.includes("BROWSER_RUN_MODE mode=selected-assets")) {
        throw new Error("missing-real-run-mode");
      }
      if (!transcript.includes("BROWSER_ASSET name=hdd")) {
        throw new Error("missing-hdd-asset");
      }
      if (expectB3 &&
          !transcript.includes("BOOT_MARK b3 browser_block=read") &&
          !transcript.includes("BOOT_MARK b3 ide=hdd")) {
        throw new Error("missing-b3-marker");
      }
    }

    return { transcript };
  } catch (error) {
    return { error: error.message || String(error), transcript: transcriptText() };
  }
}

async function main() {
  if (!pageUrl) {
    fail("missing-page-url");
  }

  const debugPort = await findFreePort();
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), "xemu-firefox-bidi."));
  const stderrRef = { text: "" };
  const firefox = spawn(firefoxBin, [
    "--headless",
    `--remote-debugging-port=${debugPort}`,
    "--profile",
    profileDir,
    "about:blank",
  ], {
    stdio: ["ignore", "ignore", "pipe"],
  });
  firefox.stderr.on("data", (chunk) => {
    stderrRef.text += String(chunk);
    if (stderrRef.text.length > 20000) {
      stderrRef.text = stderrRef.text.slice(-20000);
    }
  });

  let bidi = null;
  try {
    await waitForTcp(debugPort, firefox, stderrRef);
    bidi = await BidiClient.connect(`ws://127.0.0.1:${debugPort}/session`);
    await bidi.send("session.new", { capabilities: {} });
    const created = await bidi.send("browsingContext.create", { type: "tab" });
    const context = created.result.context;

    await bidi.send("browsingContext.navigate", { context, url: pageUrl, wait: "complete" });
    await bidi.evaluateJson(context, configurePage, { bootMs, buildDir, runtimeMode });
    await bidi.send("browsingContext.navigate", { context, url: pageUrl, wait: "complete" });
    const run = await bidi.evaluateJson(context, runPage, {
      timeoutMs,
      bootMs,
      buildDir,
      runtimeMode,
      expectB3,
      assets: assetPaths,
      pcrtcVblankMode,
      browserIcount,
      traceOptions,
    });

    if (run.error) {
      console.error("BROWSER_RUNTIME_TRANSCRIPT_BEGIN");
      console.error(run.transcript || "");
      console.error("BROWSER_RUNTIME_TRANSCRIPT_END");
      fail(run.error);
    }

    const transcript = run.transcript || "";
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
      `trace_xbe_timer_opportunity_limit=${traceOptions.xbeTimerOpportunityLimit || "default"}`,
      `trace_xbe_tick_block_limit=${traceOptions.xbeTickBlockLimit || "default"}`,
      `trace_xbe_tick_block_irq_defer=${traceOptions.xbeTickBlockIrqDefer || "default"}`,
      `trace_xbe_tick_block_irq_defer_limit=${traceOptions.xbeTickBlockIrqDeferLimit || "default"}`,
      `browser_headless_timer_pump_progress_limit=${traceOptions.browserHeadlessTimerPumpProgressLimit || "default"}`,
      `browser_headless_timer_pump_mode=${traceOptions.browserHeadlessTimerPumpMode || "default"}`,
      `browser_boot_deterministic=${traceOptions.browserBootDeterministic || "default"}`,
      `browser_boot_deterministic_timer_steps=${traceOptions.browserBootDeterministicTimerSteps || "default"}`,
      `browser_boot_deterministic_warmup_progress_limit=${traceOptions.browserBootDeterministicWarmupProgressLimit || "default"}`,
      `browser_boot_deterministic_pcrtc_prestream=${traceOptions.browserBootDeterministicPcrtcPrestream || "default"}`,
      `trace_xbe_kernel_loop_limit=${traceOptions.xbeKernelLoopLimit || "default"}`,
      `trace_xbe_kernel_loop_after_idle_limit=${traceOptions.xbeKernelLoopAfterIdleLimit || "default"}`,
      `trace_xbe_kernel_loop_min_hits=${traceOptions.xbeKernelLoopMinHits || "default"}`,
      `trace_xbe_memory_watch_phys=${traceOptions.xbeMemoryWatchPhys || "default"}`,
      `trace_xbe_memory_watch_limit=${traceOptions.xbeMemoryWatchLimit || "default"}`,
      `trace_xbe_memory_watch_access=${traceOptions.xbeMemoryWatchAccess || "default"}`,
      `trace_nv2a_user_dma_put_limit=${traceOptions.nv2aUserDmaPutLimit || "default"}`,
      `trace_xbe_tcg_timer_pump_interval=${traceOptions.xbeTcgTimerPumpInterval || "default"}`,
      `trace_xbe_tcg_timer_pump_after_idle_limit=${traceOptions.xbeTcgTimerPumpAfterIdleLimit || "default"}`,
      `trace_xbe_tcg_timer_pump_mode=${traceOptions.xbeTcgTimerPumpMode || "default"}`,
      `trace_xbe_idle_before_pfifo_transition_limit=${traceOptions.xbeIdleBeforePfifoTransitionLimit || "default"}`,
      `trace_xbe_irq_after_pfifo_empty_only=${traceOptions.xbeIrqAfterPfifoEmptyOnly || "default"}`,
      `trace_xbe_irq_watch=${traceOptions.xbeIrqWatch || "default"}`,
      `trace_call_chain=${traceOptions.callChainTrace || "default"}`,
      `b4_marker=${b4Marker ? "yes" : "no"}`,
      `display_capture=${displayCapture ? "yes" : "no"}`,
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
      `trace_xbe_timer_opportunity_limit=${traceOptions.xbeTimerOpportunityLimit || "default"}`,
      `trace_xbe_tick_block_limit=${traceOptions.xbeTickBlockLimit || "default"}`,
      `trace_xbe_tick_block_irq_defer=${traceOptions.xbeTickBlockIrqDefer || "default"}`,
      `trace_xbe_tick_block_irq_defer_limit=${traceOptions.xbeTickBlockIrqDeferLimit || "default"}`,
      `browser_headless_timer_pump_progress_limit=${traceOptions.browserHeadlessTimerPumpProgressLimit || "default"}`,
      `browser_headless_timer_pump_mode=${traceOptions.browserHeadlessTimerPumpMode || "default"}`,
      `browser_boot_deterministic=${traceOptions.browserBootDeterministic || "default"}`,
      `browser_boot_deterministic_timer_steps=${traceOptions.browserBootDeterministicTimerSteps || "default"}`,
      `browser_boot_deterministic_warmup_progress_limit=${traceOptions.browserBootDeterministicWarmupProgressLimit || "default"}`,
      `browser_boot_deterministic_pcrtc_prestream=${traceOptions.browserBootDeterministicPcrtcPrestream || "default"}`,
      `trace_xbe_kernel_loop_limit=${traceOptions.xbeKernelLoopLimit || "default"}`,
      `trace_xbe_kernel_loop_after_idle_limit=${traceOptions.xbeKernelLoopAfterIdleLimit || "default"}`,
      `trace_xbe_kernel_loop_min_hits=${traceOptions.xbeKernelLoopMinHits || "default"}`,
      `trace_xbe_memory_watch_phys=${traceOptions.xbeMemoryWatchPhys || "default"}`,
      `trace_xbe_memory_watch_limit=${traceOptions.xbeMemoryWatchLimit || "default"}`,
      `trace_xbe_memory_watch_access=${traceOptions.xbeMemoryWatchAccess || "default"}`,
      `trace_nv2a_user_dma_put_limit=${traceOptions.nv2aUserDmaPutLimit || "default"}`,
      `trace_xbe_tcg_timer_pump_interval=${traceOptions.xbeTcgTimerPumpInterval || "default"}`,
      `trace_xbe_tcg_timer_pump_after_idle_limit=${traceOptions.xbeTcgTimerPumpAfterIdleLimit || "default"}`,
      `trace_xbe_tcg_timer_pump_mode=${traceOptions.xbeTcgTimerPumpMode || "default"}`,
      `trace_xbe_idle_before_pfifo_transition_limit=${traceOptions.xbeIdleBeforePfifoTransitionLimit || "default"}`,
      `trace_xbe_irq_after_pfifo_empty_only=${traceOptions.xbeIrqAfterPfifoEmptyOnly || "default"}`,
      `trace_xbe_irq_watch=${traceOptions.xbeIrqWatch || "default"}`,
      `trace_call_chain=${traceOptions.callChainTrace || "default"}`,
      `b3=${runtimeMode === "real" && expectB3 ? "required" : "not-required"}`,
      `boot_result=${resultMatch[1]}`,
    ].join(" "));
  } finally {
    if (bidi) {
      bidi.close();
    }
    firefox.kill();
    await new Promise((resolve) => {
      firefox.once("exit", resolve);
      setTimeout(resolve, 1000);
    });
    fs.rmSync(profileDir, { recursive: true, force: true });
  }
}

main().catch((error) => fail("firefox-bidi", `message=${JSON.stringify(error.message || String(error))}`));
