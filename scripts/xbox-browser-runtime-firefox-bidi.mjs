#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const pageUrl = process.env.XEMU_BROWSER_RUNTIME_PAGE_URL ||
  `http://127.0.0.1:${process.env.XEMU_BROWSER_RUNTIME_PORT || "8765"}/browser/xbox-boot/`;
const timeoutMs = Number(process.env.XEMU_BROWSER_RUNTIME_TIMEOUT_MS || "20000");
const bootMs = process.env.XEMU_BROWSER_RUNTIME_BOOT_MS || "5000";
const buildDir = process.env.XEMU_BROWSER_RUNTIME_BUILD_DIR || "../../build-wasm";
const runtimeMode = process.env.XEMU_BROWSER_RUNTIME_MODE || "real";
const interactive = process.env.XEMU_BROWSER_RUNTIME_INTERACTIVE !== "0";
const expectB3 = process.env.XEMU_BROWSER_RUNTIME_EXPECT_B3 !== "0";
const firefoxBin = process.env.XEMU_BROWSER_RUNTIME_FIREFOX_BIN || "firefox";
const dumpTranscript = process.env.XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT === "1";

function fail(reason, detail = "") {
  console.error(`BROWSER_RUNTIME_FIREFOX_BIDI result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
  process.exit(1);
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

async function runCurrentPage({ timeoutMs, bootMs, buildDir, runtimeMode, interactive, expectB3 }) {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const transcriptText = () => document.querySelector("#logOutput")?.textContent || "";
  const dispatchChange = (element) => element.dispatchEvent(new Event("change", { bubbles: true }));
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
  const setValue = (selector, value) => {
    const element = document.querySelector(selector);
    if (!element) {
      throw new Error(`missing-control selector=${selector}`);
    }
    element.value = value;
    dispatchChange(element);
  };
  const setChecked = (selector, checked) => {
    const element = document.querySelector(selector);
    if (!element) {
      throw new Error(`missing-control selector=${selector}`);
    }
    element.checked = checked;
    dispatchChange(element);
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

  setValue("#timeoutInput", String(bootMs));
  setValue("#buildDirInput", buildDir);
  setChecked("#smokeTestInput", !interactive);

  if (runtimeMode === "real") {
    await waitFor(() => !document.querySelector("#startBtn")?.disabled, 10000, "start-button-disabled");
    document.querySelector("#startBtn").click();
  } else if (runtimeMode === "synthetic") {
    await waitFor(() => !document.querySelector("#syntheticBtn")?.disabled, 10000, "synthetic-button-disabled");
    document.querySelector("#syntheticBtn").click();
  } else {
    throw new Error(`bad-runtime-mode mode=${runtimeMode}`);
  }

  let reason = "timeout";
  try {
    await waitFor(() => {
      const text = transcriptText();
      if (text.includes("Error:") ||
          text.includes("compilation failed") ||
          text.includes("shader linking failed") ||
          text.includes("uncaught exception") ||
          text.includes("worker sent an error")) {
        reason = "error";
        return true;
      }
      if (text.includes("Run finished:")) {
        reason = "finished";
        return true;
      }
      if (interactive && text.includes("Runtime yielded to the browser event loop; interactive worker remains active.")) {
        reason = "interactive-active";
        return true;
      }
      return false;
    }, timeoutMs, "runtime-timeout");
  } catch (error) {
    if (error.message !== "runtime-timeout") {
      throw error;
    }
  }

  const transcript = transcriptText();
  const hasB3 = transcript.includes("BOOT_MARK b3 browser_block=read") ||
    transcript.includes("BOOT_MARK b3 ide=hdd");
  const hasError = transcript.includes("Error:") ||
    transcript.includes("compilation failed") ||
    transcript.includes("shader linking failed") ||
    transcript.includes("uncaught exception") ||
    transcript.includes("worker sent an error");
  const finishedMatch = transcript.match(/Run finished: ([^\s]+)/);

  return {
    reason,
    transcript,
    hasB3,
    hasError,
    finished: finishedMatch ? finishedMatch[1] : "",
    lineCount: transcript.split(/\r?\n/).filter((line) => line.length > 0).length,
    startDisabled: document.querySelector("#startBtn")?.disabled === true,
    syntheticDisabled: document.querySelector("#syntheticBtn")?.disabled === true,
    statuses: Array.from(document.querySelectorAll("output")).map((node) => ({
      id: node.id,
      text: node.textContent || "",
    })),
    expectB3,
  };
}

async function main() {
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
    const run = await bidi.evaluateJson(context, runCurrentPage, {
      timeoutMs,
      bootMs,
      buildDir,
      runtimeMode,
      interactive,
      expectB3,
    });

    if (dumpTranscript) {
      console.log("BROWSER_RUNTIME_TRANSCRIPT_BEGIN");
      console.log((run.transcript || "").trimEnd());
      console.log("BROWSER_RUNTIME_TRANSCRIPT_END");
    }

    if (run.hasError) {
      fail("page-error", `phase=${run.reason} lines=${run.lineCount}`);
    }
    if (runtimeMode === "real" && expectB3 && !run.hasB3) {
      fail("missing-b3-marker", `phase=${run.reason} lines=${run.lineCount}`);
    }

    console.log([
      "BROWSER_RUNTIME_FIREFOX_BIDI",
      "result=pass",
      `url=${JSON.stringify(pageUrl)}`,
      `mode=${runtimeMode}`,
      `interactive=${interactive ? "yes" : "no"}`,
      `phase=${run.reason}`,
      `finished=${run.finished || "none"}`,
      `b3_marker=${run.hasB3 ? "yes" : "no"}`,
      `lines=${run.lineCount}`,
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
