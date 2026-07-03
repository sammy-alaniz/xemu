import {
  SyncMemoryBlockDevice,
  chunksFromOverlaySnapshot,
} from "./block-storage.mjs";

const fixturePaths = {
  flash: "/xemu-fixtures/flash.bin",
  mcpx: "/xemu-fixtures/mcpx.bin",
  eeprom: "/xemu-fixtures/eeprom.bin",
  hdd: "/xemu-browser-block/xbox_hdd.img",
  dvd: "/xemu-browser-block/dvd.iso",
};

const browserBlockKeys = new Set(["hdd", "dvd"]);
const blockSnapshotDbName = "xemu.browserBoot.blockSnapshots.v1";
const blockSnapshotStoreName = "snapshots";
const blackDisplayFrameIntervalMs = 5000;

function makeCanvasStyle() {
  const values = new Map();
  return {
    setProperty(name, value) {
      values.set(name, value);
      this[name] = value;
    },
    removeProperty(name) {
      values.delete(name);
      delete this[name];
    },
  };
}

function installEmscriptenCanvas(offscreenCanvas) {
  if (!offscreenCanvas) {
    postError("WebGL canvas was not transferred to the worker.");
    return null;
  }

  const canvas = {
    id: "canvas",
    nodeName: "CANVAS",
    style: makeCanvasStyle(),
    parentNode: null,
    get width() {
      return offscreenCanvas.width;
    },
    set width(value) {
      offscreenCanvas.width = value;
    },
    get height() {
      return offscreenCanvas.height;
    },
    set height(value) {
      offscreenCanvas.height = value;
    },
    getContext(type, attributes) {
      return offscreenCanvas.getContext(type, attributes);
    },
    transferControlToOffscreen() {
      if (this.controlTransferredOffscreen) {
        throw new Error("canvas control was already transferred");
      }
      this.controlTransferredOffscreen = true;
      return offscreenCanvas;
    },
    getBoundingClientRect() {
      return {
        left: 0,
        top: 0,
        right: offscreenCanvas.width,
        bottom: offscreenCanvas.height,
        width: offscreenCanvas.width,
        height: offscreenCanvas.height,
      };
    },
    addEventListener() {},
    removeEventListener() {},
  };
  canvas.parentNode = {
    insertBefore() {},
    removeChild() {},
    appendChild() {},
  };

  const documentShim = {
    body: {
      clientWidth: offscreenCanvas.width,
      clientHeight: offscreenCanvas.height,
      appendChild() {},
      removeChild() {},
      requestPointerLock: null,
    },
    querySelector(selector) {
      return selector === "#canvas" || selector === "canvas" ? canvas : null;
    },
    createElement(name) {
      return String(name).toLowerCase() === "canvas" ? canvas : {};
    },
    addEventListener() {},
    removeEventListener() {},
  };

  if (!globalThis.document) {
    globalThis.document = documentShim;
  }
  if (!globalThis.window) {
    globalThis.window = globalThis;
  }
  if (typeof globalThis.matchMedia !== "function") {
    globalThis.matchMedia = () => ({
      matches: false,
      addEventListener() {},
      removeEventListener() {},
    });
  }

  return canvas;
}

function postError(message) {
  self.postMessage({ type: "error", message: String(message) });
}

function postWorkerLog(line) {
  self.postMessage({ type: "log", stream: "worker", message: String(line) });
}

globalThis.addEventListener("error", (event) => {
  const error = event.error;
  const stack = error && error.stack ? error.stack : "";
  postWorkerLog(`BROWSER_WORKER_ERROR message=${JSON.stringify(event.message || String(error || event))}${stack ? ` stack=${JSON.stringify(stack)}` : ""}`);
});

globalThis.addEventListener("unhandledrejection", (event) => {
  const reason = event.reason;
  const stack = reason && reason.stack ? reason.stack : "";
  postWorkerLog(`BROWSER_WORKER_REJECTION message=${JSON.stringify(reason && reason.message ? reason.message : String(reason))}${stack ? ` stack=${JSON.stringify(stack)}` : ""}`);
});

function errorToMessage(error) {
  if (!error) {
    return "unknown error";
  }
  const message = error.message ? String(error.message) : "";
  const stack = error.stack ? String(error.stack) : "";
  if (message && stack && !stack.includes(message)) {
    return `${message}\n${stack}`;
  }
  return stack || message || String(error);
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function tomlEscape(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

function makeConfig(assets) {
  const has = new Set(assets.map((asset) => asset.key));
  const eepromPath = has.has("eeprom") ? fixturePaths.eeprom : "/xemu-fixtures/eeprom.generated.bin";

  return `[general]
show_welcome = false
skip_boot_anim = false

[general.updates]
check = false

[display]
renderer = "OPENGL"

[perf]
cache_shaders = false

[sys]
mem_limit = "64"
avpack = "hdtv"

[sys.files]
bootrom_path = "${tomlEscape(has.has("mcpx") ? fixturePaths.mcpx : "")}"
flashrom_path = "${tomlEscape(fixturePaths.flash)}"
eeprom_path = "${tomlEscape(eepromPath)}"
hdd_path = "${tomlEscape(has.has("hdd") ? fixturePaths.hdd : "")}"
dvd_path = "${tomlEscape(has.has("dvd") ? fixturePaths.dvd : "")}"

[net]
enable = false
`;
}

async function materializeAssetBytes(asset) {
  if (asset.buffer) {
    return new Uint8Array(asset.buffer);
  }
  if (asset.blob) {
    return new Uint8Array(await asset.blob.arrayBuffer());
  }
  throw new Error(`asset has no readable storage: ${asset.key}`);
}

async function copyBlobToAccessHandle(asset, accessHandle) {
  accessHandle.truncate(0);
  let written = 0;
  const reader = asset.blob.stream().getReader();

  for (;;) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
    const actual = accessHandle.write(chunk, { at: written });
    if (actual !== chunk.byteLength) {
      throw new Error(`short OPFS write: expected=${chunk.byteLength} actual=${actual}`);
    }
    written += actual;
  }

  accessHandle.truncate(asset.size);
  accessHandle.flush();
  return written;
}

async function prepareOpfsBlock(asset) {
  if (!asset.blob || !navigator.storage || !navigator.storage.getDirectory) {
    return null;
  }

  const root = await navigator.storage.getDirectory();
  const dir = await root.getDirectoryHandle("xemu-browser-block", { create: true });
  const fileHandle = await dir.getFileHandle(`${asset.key}.img`, { create: true });
  if (typeof fileHandle.createSyncAccessHandle !== "function") {
    return null;
  }

  const accessHandle = await fileHandle.createSyncAccessHandle();
  const copied = await copyBlobToAccessHandle(asset, accessHandle);
  return {
    key: asset.key,
    name: asset.name,
    size: asset.size,
    backend: "opfs-sync",
    accessHandle,
  };
}

function openBlockSnapshotDb() {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB !== "object" || !indexedDB) {
      reject(new Error("indexedDB unavailable"));
      return;
    }

    const request = indexedDB.open(blockSnapshotDbName, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(blockSnapshotStoreName)) {
        db.createObjectStore(blockSnapshotStoreName, { keyPath: "key" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error("indexedDB open failed"));
  });
}

async function loadBlockSnapshot(asset, bytes) {
  try {
    const db = await openBlockSnapshotDb();
    const record = await new Promise((resolve, reject) => {
      const tx = db.transaction(blockSnapshotStoreName, "readonly");
      const request = tx.objectStore(blockSnapshotStoreName).get(asset.key);
      request.onsuccess = () => resolve(request.result || null);
      request.onerror = () => reject(request.error || new Error("indexedDB read failed"));
    });
    db.close();

    if (!record || !record.snapshot) {
      return 0;
    }
    if (record.size !== bytes.byteLength) {
      return 0;
    }

    const chunks = chunksFromOverlaySnapshot(record.snapshot, { size: bytes.byteLength });
    for (const [start, chunkBytes] of chunks) {
      bytes.set(chunkBytes, start);
    }
    return chunks.length;
  } catch (error) {
    return 0;
  }
}

async function prepareMemoryBlock(asset) {
  const bytes = await materializeAssetBytes(asset);
  await loadBlockSnapshot(asset, bytes);
  return {
    key: asset.key,
    name: asset.name,
    size: asset.size,
    backend: "memory",
    device: new SyncMemoryBlockDevice(bytes, { name: asset.name || asset.key }),
  };
}

async function persistBlockSnapshot(block, snapshot, serializedBytes) {
  try {
    const db = await openBlockSnapshotDb();
    await new Promise((resolve, reject) => {
      const tx = db.transaction(blockSnapshotStoreName, "readwrite");
      tx.objectStore(blockSnapshotStoreName).put({
        key: block.key,
        name: block.name,
        size: block.size,
        backend: block.backend,
        updatedAt: Date.now(),
        serializedBytes,
        snapshot,
      });
      tx.oncomplete = resolve;
      tx.onerror = () => reject(tx.error || new Error("indexedDB transaction failed"));
      tx.onabort = () => reject(tx.error || new Error("indexedDB transaction aborted"));
    });
    db.close();
  } catch (error) {
  }
}

async function materializeAssets(assets) {
  const materialized = [];
  for (const asset of assets) {
    if (browserBlockKeys.has(asset.key)) {
      materialized.push(asset);
      continue;
    }
    materialized.push({
      ...asset,
      buffer: (await materializeAssetBytes(asset)).buffer,
      blob: null,
    });
  }
  return materialized;
}

function writeFixtureFiles(FS, assets) {
  FS.mkdir("/xemu-fixtures");
  for (const asset of assets) {
    if (browserBlockKeys.has(asset.key)) {
      continue;
    }
    FS.writeFile(fixturePaths[asset.key], new Uint8Array(asset.buffer));
  }
  if (!assets.some((asset) => asset.key === "eeprom")) {
    FS.writeFile("/xemu-fixtures/eeprom.generated.bin", new Uint8Array(256));
  }
}

function eepromPathForAssets(assets) {
  return assets.some((asset) => asset.key === "eeprom") ? fixturePaths.eeprom : "/xemu-fixtures/eeprom.generated.bin";
}

function emitEeprom(FS, path, reason) {
  try {
    const bytes = FS.readFile(path);
    if (bytes.length === 256) {
      self.postMessage({ type: "eeprom", base64: bytesToBase64(bytes), reason });
    }
  } catch (error) {
  }
}

function validateAssets(assets) {
  const seen = new Set();
  const requiredSizes = new Map([
    ["mcpx", 512],
    ["eeprom", 256],
  ]);

  for (const asset of assets) {
    if (!fixturePaths[asset.key]) {
      return `unknown-asset:${asset.key}`;
    }
    if (seen.has(asset.key)) {
      return `duplicate-asset:${asset.key}`;
    }
    seen.add(asset.key);
    const requiredSize = requiredSizes.get(asset.key);
    if (requiredSize && asset.size !== requiredSize) {
      return `bad-size:${asset.key}:expected=${requiredSize}:actual=${asset.size}`;
    }
    if (!(asset.buffer instanceof ArrayBuffer) && !asset.blob) {
      return `missing-buffer:${asset.key}`;
    }
    if ((asset.key !== "hdd" && asset.key !== "dvd") && !(asset.buffer instanceof ArrayBuffer)) {
      return `buffer-required:${asset.key}`;
    }
  }

  if (!seen.has("flash")) {
    return "missing-flash";
  }

  return "";
}

async function prepareBrowserBlocks(assets) {
  const byPath = new Map();
  for (const asset of assets) {
    if (!browserBlockKeys.has(asset.key)) {
      continue;
    }
    let block = null;
    try {
      block = await prepareOpfsBlock(asset);
    } catch (error) {
    }
    if (!block) {
      block = await prepareMemoryBlock(asset);
    }
    byPath.set(fixturePaths[asset.key], block);
  }
  return { byPath, byId: new Map(), nextId: 1 };
}

function installBrowserBlockCallbacks(moduleArg, registry) {
  const heap = () => globalThis.xemuBrowserBlockHeap || moduleArg.HEAPU8;

  moduleArg.xemuBrowserBlockOpen = (path, writable) => {
    const block = registry.byPath.get(path);
    if (!block) {
      return -1;
    }
    const id = registry.nextId++;
    registry.byId.set(id, block);
    return id;
  };

  moduleArg.xemuBrowserBlockGetSize = (id) => {
    const block = registry.byId.get(id);
    return block ? block.size : -1;
  };

  moduleArg.xemuBrowserBlockRead = (id, offset, ptr, bytes) => {
    const block = registry.byId.get(id);
    offset = Number(offset);
    if (!block || offset < 0 || bytes < 0 || offset + bytes > block.size) {
      return -1;
    }
    if (block.accessHandle) {
      const actual = block.accessHandle.read(heap().subarray(ptr, ptr + bytes), { at: offset });
      if (actual !== bytes) {
        return -1;
      }
    } else {
      block.device.readInto(heap().subarray(ptr, ptr + bytes), offset);
    }
    return 0;
  };

  moduleArg.xemuBrowserBlockWrite = (id, offset, ptr, bytes) => {
    const block = registry.byId.get(id);
    offset = Number(offset);
    if (!block || offset < 0 || bytes < 0 || offset + bytes > block.size) {
      return -1;
    }
    if (block.accessHandle) {
      const actual = block.accessHandle.write(heap().subarray(ptr, ptr + bytes), { at: offset });
      if (actual !== bytes) {
        return -1;
      }
    } else {
      block.device.writeFrom(heap().subarray(ptr, ptr + bytes), offset);
    }
    return 0;
  };

  moduleArg.xemuBrowserBlockFlush = (id) => {
    const block = registry.byId.get(id);
    if (block && block.accessHandle) {
      block.accessHandle.flush();
    } else if (block) {
      const snapshot = block.device.flushSnapshot();
      if (snapshot) {
        const serialized = JSON.stringify(snapshot);
        void persistBlockSnapshot(block, snapshot, serialized.length);
      }
    }
    return block ? 0 : -1;
  };

  moduleArg.xemuBrowserBlockClose = (id) => {
    const block = registry.byId.get(id);
    if (block && block.accessHandle) {
      block.accessHandle.close();
    }
    registry.byId.delete(id);
  };

  globalThis.xemuBrowserBlockOpen = moduleArg.xemuBrowserBlockOpen;
  globalThis.xemuBrowserBlockGetSize = moduleArg.xemuBrowserBlockGetSize;
  globalThis.xemuBrowserBlockRead = moduleArg.xemuBrowserBlockRead;
  globalThis.xemuBrowserBlockWrite = moduleArg.xemuBrowserBlockWrite;
  globalThis.xemuBrowserBlockFlush = moduleArg.xemuBrowserBlockFlush;
  globalThis.xemuBrowserBlockClose = moduleArg.xemuBrowserBlockClose;
}

async function runBoot({ buildDir, timeoutMs, smokeTest = true, assets, canvas }) {
  const validationError = validateAssets(assets);
  if (validationError) {
    self.postMessage({ type: "done", result: "invalid-assets" });
    return;
  }
  const browserBlocks = await prepareBrowserBlocks(assets);
  const materializedAssets = await materializeAssets(assets);

  const moduleUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.js`, self.location.href).href;
  const wasmUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.wasm`, self.location.href).href;
  const emscriptenCanvas = installEmscriptenCanvas(canvas);
  const { default: Factory } = await import(moduleUrl);
  let moduleFS = null;
  let eepromPath = eepromPathForAssets(assets);
  let timeout = null;
  let doneSent = false;
  let displayFrameSerial = 0;
  let lastBlackDisplayPostMs = 0;
  let displayHasPostedNonblack = false;
  let displayHasLoggedNonblack = false;

  const finishRun = (result, reason) => {
    if (doneSent) {
      return;
    }
    doneSent = true;
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, reason);
    }
    self.postMessage({ type: "done", result });
  };

  if (smokeTest) {
    timeout = setTimeout(() => {
      finishRun("timeout", "timeout");
    }, timeoutMs);
  }

  const moduleArguments = [
    "-config_path", "/xemu-fixtures/xemu-smoke.toml",
    "-headless_boot_ms", String(smokeTest ? timeoutMs : 0),
  ];

  if (!smokeTest) {
    moduleArguments.push("-no-shutdown");
  }

  const postLog = (stream, line) => {
    const text = String(line || "");
    if (text) {
      self.postMessage({ type: "log", stream, message: text });
    }
  };

  const moduleArg = {
    locateFile(path) {
      if (path.endsWith(".wasm")) {
        return wasmUrl;
      }
      return new URL(`${buildDir.replace(/\/$/, "")}/${path}`, self.location.href).href;
    },
    arguments: moduleArguments,
    canvas: emscriptenCanvas,
    print(line) {
      postLog("stdout", line);
    },
    printErr(line) {
      postLog("stderr", line);
    },
    onExit(code) {
      postLog("xemu", `Exited with code ${code}`);
      if (!smokeTest) {
        finishRun(`exited-${code}`, "exit");
      }
    },
  };
  moduleArg.xemuBrowserDisplayUpdate = (ptr, width, height, stride, source = "unknown") => {
    const heap = moduleArg.HEAPU8 || globalThis.xemuBrowserDisplayHeap || globalThis.xemuBrowserBlockHeap;
    if (!heap) {
      throw new Error("display heap unavailable");
    }
    source = String(source || "unknown");
    displayFrameSerial += 1;
    let nonblack = false;
    const sampleStride = 1024 * 4;
    const fullScan = !displayHasPostedNonblack && displayFrameSerial % 30 === 0;

    for (let y = 0; y < height && !nonblack; y++) {
      const row = ptr + y * stride;
      const rowEnd = row + width * 4;
      const step = fullScan ? 4 : sampleStride;

      for (let offset = row; offset < rowEnd; offset += step) {
        if (heap[offset] !== 0 || heap[offset + 1] !== 0 || heap[offset + 2] !== 0) {
          nonblack = true;
          break;
        }
      }
    }

    if (!nonblack) {
      const now = Date.now();
      if (displayFrameSerial === 1 || displayFrameSerial % 300 === 0) {
        postLog("display", `BROWSER_WORKER_DISPLAY frame=${displayFrameSerial} source=${source} width=${width} height=${height} nonblack=no forwarded=${lastBlackDisplayPostMs && now - lastBlackDisplayPostMs < blackDisplayFrameIntervalMs ? "no" : "yes"}`);
      }
      if (lastBlackDisplayPostMs && now - lastBlackDisplayPostMs < blackDisplayFrameIntervalMs) {
        return;
      }
      lastBlackDisplayPostMs = now;
    } else {
      if (!displayHasLoggedNonblack) {
        postLog("display", `BROWSER_WORKER_DISPLAY frame=${displayFrameSerial} source=${source} width=${width} height=${height} nonblack=yes forwarded=yes`);
        displayHasLoggedNonblack = true;
      }
      displayHasPostedNonblack = true;
    }

    const pixels = new Uint8ClampedArray(width * height * 4);

    for (let y = 0; y < height; y++) {
      const start = ptr + y * stride;
      const end = start + width * 4;
      pixels.set(heap.subarray(start, end), y * width * 4);
    }

    self.postMessage({
      type: "display-frame",
      width,
      height,
      source,
      nonblack,
      pixels: pixels.buffer,
    }, [pixels.buffer]);
  };
  globalThis.xemuBrowserDisplayUpdate = moduleArg.xemuBrowserDisplayUpdate;
  installBrowserBlockCallbacks(moduleArg, browserBlocks);

  moduleArg.preRun = [() => {
    moduleFS = moduleArg.FS;
    writeFixtureFiles(moduleArg.FS, materializedAssets);
    moduleArg.FS.writeFile("/xemu-fixtures/xemu-smoke.toml", makeConfig(materializedAssets));
  }];

  try {
    await Factory(moduleArg);
    clearTimeout(timeout);
    if (smokeTest) {
      finishRun("pass", "module-return");
      return;
    }

    if (!doneSent) {
      postLog("xemu", "Runtime yielded to the browser event loop; interactive worker remains active.");
    }
    await new Promise(() => {});
  } catch (error) {
    clearTimeout(timeout);
    postError(errorToMessage(error));
    finishRun("fail", "error");
  }
}

self.onmessage = (event) => {
  if (!event.data || event.data.type !== "start") {
    return;
  }
  runBoot(event.data).catch((error) => {
    postError(errorToMessage(error));
    self.postMessage({ type: "done", result: "fail" });
  });
};
