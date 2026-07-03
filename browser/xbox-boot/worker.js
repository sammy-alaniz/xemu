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

function postError(message) {
  self.postMessage({ type: "error", message: String(message) });
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
renderer = "NULL"

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

async function runBoot({ buildDir, timeoutMs, smokeTest = true, assets }) {
  const validationError = validateAssets(assets);
  if (validationError) {
    self.postMessage({ type: "done", result: "invalid-assets" });
    return;
  }
  const browserBlocks = await prepareBrowserBlocks(assets);
  const materializedAssets = await materializeAssets(assets);

  const moduleUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.js`, self.location.href).href;
  const wasmUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.wasm`, self.location.href).href;
  const { default: Factory } = await import(moduleUrl);
  let moduleFS = null;
  let eepromPath = eepromPathForAssets(assets);
  let timeout = null;

  if (smokeTest) {
    timeout = setTimeout(() => {
      if (moduleFS) {
        emitEeprom(moduleFS, eepromPath, "timeout");
      }
      self.postMessage({ type: "done", result: "timeout" });
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
    print(line) {
      postLog("stdout", line);
    },
    printErr(line) {
      postLog("stderr", line);
    },
    onExit(code) {
      postLog("xemu", `Exited with code ${code}`);
    },
  };
  moduleArg.xemuBrowserDisplayUpdate = (ptr, width, height, stride) => {
    const heap = moduleArg.HEAPU8;
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
      pixels: pixels.buffer,
    }, [pixels.buffer]);
  };
  installBrowserBlockCallbacks(moduleArg, browserBlocks);

  moduleArg.preRun = [() => {
    moduleFS = moduleArg.FS;
    writeFixtureFiles(moduleArg.FS, materializedAssets);
    moduleArg.FS.writeFile("/xemu-fixtures/xemu-smoke.toml", makeConfig(materializedAssets));
  }];

  try {
    await Factory(moduleArg);
    clearTimeout(timeout);
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, "module-return");
    }
    self.postMessage({
      type: "done",
      result: smokeTest ? "pass" : "module-returned",
    });
  } catch (error) {
    clearTimeout(timeout);
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, "error");
    }
    postError(error && error.stack ? error.stack : error);
    self.postMessage({ type: "done", result: "fail" });
  }
}

self.onmessage = (event) => {
  if (!event.data || event.data.type !== "start") {
    return;
  }
  runBoot(event.data).catch((error) => {
    postError(error && error.stack ? error.stack : error);
    self.postMessage({ type: "done", result: "fail" });
  });
};
