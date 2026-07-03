#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");

function usage() {
  console.log(`Usage: scripts/capture-browser-boot-strip.mjs [options]

Capture the browser boot display canvas at a fixed sample rate. This script
does not compare or grade frames. It only saves PNGs for human visual review.

Options:
  --out DIR          Output directory. Default: /tmp/xemu-boot-strips/browser-<timestamp>
  --seconds N       Capture duration in seconds. Default: 45
  --fps N           Capture rate. Default: 2
  --build-dir DIR   Browser wasm build dir as seen by the page. Default: ../../build-wasm
  --page-url URL    Use an already-running browser boot page instead of starting the server.
  --firefox BIN     Firefox binary. Default: firefox
  --help            Show this help.
`);
}

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, "0");
  return [
    now.getFullYear(),
    pad(now.getMonth() + 1),
    pad(now.getDate()),
  ].join("") + "-" + [
    pad(now.getHours()),
    pad(now.getMinutes()),
    pad(now.getSeconds()),
  ].join("");
}

function parseArgs(argv) {
  const options = {
    outDir: process.env.XEMU_BROWSER_CAPTURE_OUT || path.join(os.tmpdir(), "xemu-boot-strips", `browser-${timestamp()}`),
    seconds: Number(process.env.XEMU_BROWSER_CAPTURE_SECONDS || "45"),
    fps: Number(process.env.XEMU_BROWSER_CAPTURE_FPS || "2"),
    buildDir: process.env.XEMU_BROWSER_RUNTIME_BUILD_DIR || "../../build-wasm",
    pageUrl: process.env.XEMU_BROWSER_RUNTIME_PAGE_URL || "",
    firefoxBin: process.env.XEMU_BROWSER_RUNTIME_FIREFOX_BIN || "firefox",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else if (arg === "--out") {
      options.outDir = argv[++index];
    } else if (arg === "--seconds") {
      options.seconds = Number(argv[++index]);
    } else if (arg === "--fps") {
      options.fps = Number(argv[++index]);
    } else if (arg === "--build-dir") {
      options.buildDir = argv[++index];
    } else if (arg === "--page-url") {
      options.pageUrl = argv[++index];
    } else if (arg === "--firefox") {
      options.firefoxBin = argv[++index];
    } else {
      throw new Error(`unknown option: ${arg}`);
    }
  }

  if (!(options.seconds > 0)) {
    throw new Error("--seconds must be greater than zero");
  }
  if (!(options.fps > 0)) {
    throw new Error("--fps must be greater than zero");
  }

  return options;
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

async function waitForTcp(port, child, stderrRef, label) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    if (child && child.exitCode !== null) {
      throw new Error(`${label}-exited exit=${child.exitCode} stderr=${JSON.stringify(stderrRef.text.slice(-2000))}`);
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
  throw new Error(`${label}-tcp-timeout stderr=${JSON.stringify(stderrRef.text.slice(-2000))}`);
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

async function capturePageBootStrip({ seconds, fps, buildDir }) {
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
  const lastDisplayLine = () => {
    const lines = transcriptText().trimEnd().split(/\r?\n/).filter(Boolean);
    for (let index = lines.length - 1; index >= 0; index -= 1) {
      if (lines[index].includes("BROWSER_DISPLAY_FRAME") ||
          lines[index].includes("BROWSER_WORKER_DISPLAY")) {
        return lines[index];
      }
    }
    return "";
  };

  await waitFor(() => document.querySelector("#capabilities .status-pill"), 10000, "capabilities-timeout");
  setValue("#buildDirInput", buildDir);
  setChecked("#smokeTestInput", false);

  await waitFor(() => !document.querySelector("#startBtn")?.disabled, 15000, "start-button-disabled");
  document.querySelector("#startBtn").click();

  const intervalMs = 1000 / fps;
  const frameCount = Math.max(1, Math.round(seconds * fps));
  const frames = [];
  const startedAt = performance.now();

  for (let index = 0; index < frameCount; index += 1) {
    const targetElapsed = index * intervalMs;
    const waitMs = startedAt + targetElapsed - performance.now();
    if (waitMs > 0) {
      await sleep(waitMs);
    }

    const canvas = document.querySelector("#displayCanvas");
    if (!canvas) {
      throw new Error("display-canvas-missing");
    }
    frames.push({
      index,
      elapsedMs: Math.round(performance.now() - startedAt),
      width: canvas.width,
      height: canvas.height,
      displayLine: lastDisplayLine(),
      dataUrl: canvas.toDataURL("image/png"),
    });
  }

  const stop = document.querySelector("#stopBtn");
  if (stop && !stop.disabled) {
    stop.click();
  }

  return {
    frames,
    transcript: transcriptText(),
  };
}

function writePngFrames(outDir, frames) {
  for (const frame of frames) {
    const match = /^data:image\/png;base64,(.+)$/.exec(frame.dataUrl);
    if (!match) {
      throw new Error(`bad data URL for frame ${frame.index}`);
    }
    const fileName = `${String(frame.index).padStart(4, "0")}.png`;
    fs.writeFileSync(path.join(outDir, fileName), Buffer.from(match[1], "base64"));
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  fs.mkdirSync(options.outDir, { recursive: true });
  const outDir = path.resolve(options.outDir);
  const firefoxPort = await findFreePort();
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), "xemu-firefox-capture."));
  const children = [];
  let pageUrl = options.pageUrl;

  try {
    if (!pageUrl) {
      const serverPort = await findFreePort();
      const server = spawn("python3", [
        path.join(repoRoot, "scripts", "serve-xbox-browser-boot.py"),
        "--host", "127.0.0.1",
        "--port", String(serverPort),
        "--directory", repoRoot,
      ], {
        cwd: repoRoot,
        stdio: ["ignore", "ignore", "pipe"],
      });
      children.push(server);
      const serverStderr = { text: "" };
      server.stderr.on("data", (chunk) => {
        serverStderr.text += String(chunk);
      });
      await waitForTcp(serverPort, server, serverStderr, "asset-server");
      pageUrl = `http://127.0.0.1:${serverPort}/browser/xbox-boot/`;
    }

    const firefoxStderr = { text: "" };
    const firefox = spawn(options.firefoxBin, [
      "--headless",
      `--remote-debugging-port=${firefoxPort}`,
      "--profile",
      profileDir,
      "about:blank",
    ], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    children.push(firefox);
    firefox.stderr.on("data", (chunk) => {
      firefoxStderr.text += String(chunk);
      if (firefoxStderr.text.length > 20000) {
        firefoxStderr.text = firefoxStderr.text.slice(-20000);
      }
    });

    await waitForTcp(firefoxPort, firefox, firefoxStderr, "firefox");
    const bidi = await BidiClient.connect(`ws://127.0.0.1:${firefoxPort}/session`);
    try {
      await bidi.send("session.new", { capabilities: {} });
      const created = await bidi.send("browsingContext.create", { type: "tab" });
      const context = created.result.context;
      await bidi.send("browsingContext.navigate", { context, url: pageUrl, wait: "complete" });
      const capture = await bidi.evaluateJson(context, capturePageBootStrip, {
        seconds: options.seconds,
        fps: options.fps,
        buildDir: options.buildDir,
      });

      writePngFrames(outDir, capture.frames);
      fs.writeFileSync(path.join(outDir, "transcript.txt"), `${capture.transcript.trimEnd()}\n`);
      fs.writeFileSync(path.join(outDir, "manifest.json"), `${JSON.stringify({
        kind: "browser-boot-strip",
        capturedFrames: capture.frames.length,
        fps: options.fps,
        seconds: options.seconds,
        buildDir: options.buildDir,
        pageUrl,
        transcript: "transcript.txt",
        review: "human-eyeball-only",
        frames: capture.frames.map(({ dataUrl, ...frame }) => ({
          ...frame,
          file: `${String(frame.index).padStart(4, "0")}.png`,
        })),
      }, null, 2)}\n`);

      console.error(`Captured ${capture.frames.length} browser frames into ${outDir}`);
      console.log(outDir);
    } finally {
      bidi.close();
    }
  } finally {
    for (const child of children.reverse()) {
      child.kill();
    }
    await Promise.all(children.map((child) => new Promise((resolve) => {
      child.once("exit", resolve);
      setTimeout(resolve, 1000);
    })));
    fs.rmSync(profileDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(`capture-browser-boot-strip result=fail message=${JSON.stringify(error.message || String(error))}`);
  process.exit(1);
});
