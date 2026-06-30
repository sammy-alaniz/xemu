#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const pageUrl = process.env.XEMU_BROWSER_BLOCK_PERSISTENCE_PAGE_URL;
const timeoutMs = Number(process.env.XEMU_BROWSER_BLOCK_PERSISTENCE_TIMEOUT || "15000");
const firefoxBin = process.env.XEMU_BROWSER_RUNTIME_FIREFOX_BIN || "firefox";

function fail(reason, detail = "") {
  console.error(`BROWSER_BLOCK_PERSISTENCE_SMOKE result=fail reason=${reason}${detail ? ` ${detail}` : ""}`);
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

async function persistencePage({ timeoutMs }) {
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
  await waitFor(() => document.querySelector("#capabilities"), timeoutMs, "page-timeout");

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
}

async function main() {
  if (!pageUrl) {
    fail("missing-page-url");
  }

  const debugPort = await findFreePort();
  const profileDir = mkdtempSync(path.join(os.tmpdir(), "xemu-firefox-block."));
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
    const result = await bidi.evaluateJson(context, persistencePage, { timeoutMs });
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
