#!/usr/bin/env node

import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const pageUrl = process.env.XEMU_BROWSER_DISPLAY_CAPTURE_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_DISPLAY_CAPTURE_TIMEOUT || "15000");
const captureLog = process.env.XEMU_BROWSER_DISPLAY_CAPTURE_LOG;
const firefoxBin = process.env.XEMU_BROWSER_RUNTIME_FIREFOX_BIN || "firefox";

function fail(reason, detail = "") {
  console.error(`BROWSER_DISPLAY_CAPTURE_SMOKE result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
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
    return JSON.parse(evaluation.result.value);
  }

  close() {
    this.ws.close();
  }
}

async function capturePage({ timeoutMs }) {
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

  await waitFor(() => document.querySelector("#displayCanvas"), timeoutMs, "canvas-timeout");
  await waitFor(() => typeof globalThis.xemuBrowserDisplayCapture === "function", timeoutMs, "capture-hook-timeout");
  const first = await globalThis.xemuBrowserDisplayCapture();
  const second = await globalThis.xemuBrowserDisplayCapture({ log: false });
  const transcript = document.querySelector("#logOutput")?.textContent || "";
  return { first, second, transcript };
}

async function main() {
  if (!pageUrl) {
    fail("missing-page-url");
  }
  if (!captureLog) {
    fail("missing-capture-log");
  }

  const debugPort = await findFreePort();
  const profileDir = mkdtempSync(path.join(os.tmpdir(), "xemu-firefox-display."));
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
    const { first, second, transcript } = await bidi.evaluateJson(context, capturePage, { timeoutMs });

    if (!first.nonempty || !second.nonempty) {
      fail("empty-canvas");
    }
    if (first.hash !== second.hash) {
      fail("unstable-hash", `first=${first.hash} second=${second.hash}`);
    }
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
    if (bidi) {
      bidi.close();
    }
    firefox.kill();
    await new Promise((resolve) => {
      firefox.once("exit", resolve);
      setTimeout(resolve, 1000);
    });
    rmSync(profileDir, { recursive: true, force: true });
  }
}

main().catch((error) => fail("firefox-bidi", `message=${JSON.stringify(error.message || String(error))}`));
