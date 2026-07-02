import {
  BlobBlockDevice,
  MemoryBlockDevice,
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

function postLog(line) {
  self.postMessage({ type: "log", line });
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
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

async function blockDeviceForAsset(asset) {
  if (asset.blob) {
    return new BlobBlockDevice(asset.blob, { name: asset.name || asset.key });
  }
  return new MemoryBlockDevice(new Uint8Array(asset.buffer), { name: asset.name || asset.key });
}

async function materializeAssetBytes(asset) {
  if (asset.buffer) {
    return new Uint8Array(asset.buffer);
  }
  if (asset.blob) {
    postLog(`BROWSER_BLOCK_MATERIALIZE asset=${asset.key} bytes=${asset.size} mode=temporary-memfs-bridge`);
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
  postLog(`BROWSER_BLOCK_BACKING result=pass asset=${asset.key} backend=opfs-sync bytes=${copied}`);
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
      postLog(`BROWSER_BLOCK_SNAPSHOT_LOAD result=skip asset=${asset.key} source=indexedDB reason=missing`);
      return 0;
    }
    if (record.size !== bytes.byteLength) {
      postLog(`BROWSER_BLOCK_SNAPSHOT_LOAD result=skip asset=${asset.key} source=indexedDB reason=size-mismatch expected=${bytes.byteLength} actual=${record.size}`);
      return 0;
    }

    const chunks = chunksFromOverlaySnapshot(record.snapshot, { size: bytes.byteLength });
    for (const [start, chunkBytes] of chunks) {
      bytes.set(chunkBytes, start);
    }
    postLog(`BROWSER_BLOCK_SNAPSHOT_LOAD result=pass asset=${asset.key} source=indexedDB chunks=${chunks.length} serialized_bytes=${record.serializedBytes || "unknown"}`);
    return chunks.length;
  } catch (error) {
    postLog(`BROWSER_BLOCK_SNAPSHOT_LOAD result=skip asset=${asset.key} source=indexedDB reason=${JSON.stringify(error.message || String(error))}`);
    return 0;
  }
}

async function prepareMemoryBlock(asset) {
  const bytes = await materializeAssetBytes(asset);
  const restoredChunks = await loadBlockSnapshot(asset, bytes);
  postLog(`BROWSER_BLOCK_BACKING result=pass asset=${asset.key} backend=memory bytes=${bytes.byteLength} restored_chunks=${restoredChunks}`);
  return {
    key: asset.key,
    name: asset.name,
    size: asset.size,
    backend: "memory",
    device: new SyncMemoryBlockDevice(bytes, { name: asset.name || asset.key }),
  };
}

const traceOptionSpecs = [
  {
    key: "xbeExecProbeLimit",
    name: "xbe_exec_probe_limit",
    fileName: "xbe_exec_probe_limit.txt",
  },
  {
    key: "xbeExecProbeStride",
    name: "xbe_exec_probe_stride",
    fileName: "xbe_exec_probe_stride.txt",
  },
  {
    key: "xbePhysCompareLimit",
    name: "xbe_phys_compare_limit",
    fileName: "xbe_phys_compare_limit.txt",
  },
  {
    key: "xbeKernelLoopLimit",
    name: "xbe_kernel_loop_limit",
    fileName: "xbe_kernel_loop_limit.txt",
  },
  {
    key: "xbeKernelLoopAfterIdleLimit",
    name: "xbe_kernel_loop_after_idle_limit",
    fileName: "xbe_kernel_loop_after_idle_limit.txt",
  },
  {
    key: "xbeKernelLoopMinHits",
    name: "xbe_kernel_loop_min_hits",
    fileName: "xbe_kernel_loop_min_hits.txt",
  },
  {
    key: "xbeMemoryWatchPhys",
    name: "xbe_memory_watch_phys",
    fileName: "xbe_memory_watch_phys.txt",
  },
  {
    key: "xbeMemoryWatchLimit",
    name: "xbe_memory_watch_limit",
    fileName: "xbe_memory_watch_limit.txt",
  },
  {
    key: "xbeMemoryWatchAccess",
    name: "xbe_memory_watch_access",
    fileName: "xbe_memory_watch_access.txt",
  },
  {
    key: "nv2aUserDmaPutLimit",
    name: "nv2a_user_dma_put_limit",
    fileName: "nv2a_user_dma_put_limit.txt",
  },
  {
    key: "xbePicIrqLimit",
    name: "xbe_pic_irq_limit",
    fileName: "xbe_pic_irq_limit.txt",
  },
  {
    key: "xbeCpuHardIrqLimit",
    name: "xbe_cpu_hard_irq_limit",
    fileName: "xbe_cpu_hard_irq_limit.txt",
  },
  {
    key: "xbeIretLimit",
    name: "xbe_iret_limit",
    fileName: "xbe_iret_limit.txt",
  },
  {
    key: "xbePitIrqLimit",
    name: "xbe_pit_irq_limit",
    fileName: "xbe_pit_irq_limit.txt",
  },
  {
    key: "xbeMainLoopTimerLimit",
    name: "xbe_main_loop_timer_limit",
    fileName: "xbe_main_loop_timer_limit.txt",
  },
  {
    key: "xbeTimerOpportunityLimit",
    name: "xbe_timer_opportunity_limit",
    fileName: "xbe_timer_opportunity_limit.txt",
  },
  {
    key: "xbeEdgeDecisionLimit",
    name: "xbe_edge_decision_limit",
    fileName: "xbe_edge_decision_limit.txt",
  },
  {
    key: "xbeTickBlockLimit",
    name: "xbe_tick_block_limit",
    fileName: "xbe_tick_block_limit.txt",
  },
  {
    key: "xbeTickBlockIrqDefer",
    name: "xbe_tick_block_irq_defer",
    fileName: "xbe_tick_block_irq_defer.txt",
  },
  {
    key: "xbeTickBlockIrqDeferLimit",
    name: "xbe_tick_block_irq_defer_limit",
    fileName: "xbe_tick_block_irq_defer_limit.txt",
  },
  {
    key: "browserHeadlessTimerPumpProgressLimit",
    name: "browser_headless_timer_pump_progress_limit",
    fileName: "browser_headless_timer_pump_progress_limit.txt",
  },
  {
    key: "browserHeadlessTimerPumpMode",
    name: "browser_headless_timer_pump_mode",
    fileName: "browser_headless_timer_pump_mode.txt",
  },
  {
    key: "browserBootDeterministic",
    name: "browser_boot_deterministic",
    fileName: "browser_boot_deterministic.txt",
  },
  {
    key: "browserBootDeterministicTimerSteps",
    name: "browser_boot_deterministic_timer_steps",
    fileName: "browser_boot_deterministic_timer_steps.txt",
  },
  {
    key: "browserBootDeterministicWarmupProgressLimit",
    name: "browser_boot_deterministic_warmup_progress_limit",
    fileName: "browser_boot_deterministic_warmup_progress_limit.txt",
  },
  {
    key: "browserBootDeterministicPcrtcPrestream",
    name: "browser_boot_deterministic_pcrtc_prestream",
    fileName: "browser_boot_deterministic_pcrtc_prestream.txt",
  },
  {
    key: "xbeTcgTimerPumpInterval",
    name: "xbe_tcg_timer_pump_interval",
    fileName: "xbe_tcg_timer_pump_interval.txt",
  },
  {
    key: "xbeTcgTimerPumpAfterIdleLimit",
    name: "xbe_tcg_timer_pump_after_idle_limit",
    fileName: "xbe_tcg_timer_pump_after_idle_limit.txt",
  },
  {
    key: "xbeTcgTimerPumpMode",
    name: "xbe_tcg_timer_pump_mode",
    fileName: "xbe_tcg_timer_pump_mode.txt",
  },
  {
    key: "xbeIdleBeforePfifoTransitionLimit",
    name: "xbe_idle_before_pfifo_transition_limit",
    fileName: "xbe_idle_before_pfifo_transition_limit.txt",
  },
  {
    key: "xbeIrqAfterPfifoEmptyOnly",
    name: "xbe_irq_after_pfifo_empty_only",
    fileName: "xbe_irq_after_pfifo_empty_only.txt",
  },
  {
    key: "xbeIrqWatch",
    name: "xbe_irq_watch",
    fileName: "xbe_irq_watch.txt",
  },
  {
    key: "callChainTrace",
    name: "call_chain_trace",
    fileName: "call_chain_trace.txt",
  },
];

function writeTraceOptions(fs, traceOptions = {}) {
  for (const spec of traceOptionSpecs) {
    const value = String(traceOptions[spec.key] || "").trim();
    if (!value) {
      continue;
    }

    const path = `/xemu-fixtures/${spec.fileName}`;
    fs.writeFile(path, `${value}\n`);
    postLog(`BROWSER_DIAGNOSTIC_APPLY name=${spec.name} value=${value} target=${path}`);
  }
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
    postLog(`BROWSER_BLOCK_SNAPSHOT_PERSIST result=pass asset=${block.key} target=indexedDB serialized_bytes=${serializedBytes}`);
  } catch (error) {
    postLog(`BROWSER_BLOCK_SNAPSHOT_PERSIST result=skip asset=${block.key} target=indexedDB reason=${JSON.stringify(error.message || String(error))}`);
  }
}

async function probeBlockAsset(asset) {
  if (asset.key !== "hdd" && asset.key !== "dvd") {
    return;
  }
  const device = await blockDeviceForAsset(asset);
  const sectorCount = Math.floor(device.size / device.sectorSize);
  if (sectorCount === 0) {
    postLog(`BROWSER_BLOCK_PROBE result=skip asset=${asset.key} reason=too-small size=${device.size}`);
    return;
  }

  const lbas = Array.from(new Set([
    0,
    Math.floor(sectorCount / 2),
    sectorCount - 1,
  ]));
  const hashes = [];
  for (const lba of lbas) {
    const bytes = await device.readSectors(lba, 1);
    hashes.push(`${lba}:${(await sha256Hex(bytes)).slice(0, 16)}`);
  }

  postLog([
    "BROWSER_BLOCK_PROBE",
    "result=pass",
    `asset=${asset.key}`,
    `source=${asset.blob ? "blob" : "buffer"}`,
    `size=${device.size}`,
    `sector_size=${device.sectorSize}`,
    `sector_reads=${lbas.length}`,
    `bytes_read=${device.stats.bytesRead}`,
    `hashes=${hashes.join(",")}`,
  ].join(" "));
}

async function probeBlockAssets(assets) {
  for (const asset of assets) {
    await probeBlockAsset(asset);
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
      postLog(`BROWSER_EEPROM_EXPORT result=pass reason=${reason} bytes=256 path=${path}`);
    } else {
      postLog(`BROWSER_EEPROM_EXPORT result=skip reason=bad-size size=${bytes.length} path=${path}`);
    }
  } catch (error) {
    postLog(`BROWSER_EEPROM_EXPORT result=skip reason=read-failed message=${JSON.stringify(error.message || String(error))}`);
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
      postLog(`BROWSER_BLOCK_BACKING result=fail asset=${asset.key} backend=opfs-sync message=${JSON.stringify(error.message || String(error))}`);
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
      postLog(`BROWSER_BLOCK_OPEN result=fail path=${JSON.stringify(path)}`);
      return -1;
    }
    const id = registry.nextId++;
    registry.byId.set(id, block);
    postLog(`BROWSER_BLOCK_OPEN result=pass id=${id} asset=${block.key} backend=${block.backend} writable=${writable ? "yes" : "no"} size=${block.size}`);
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
      postLog(`BROWSER_BLOCK_READ result=fail id=${id} offset=${offset} bytes=${bytes}`);
      return -1;
    }
    if (block.accessHandle) {
      const actual = block.accessHandle.read(heap().subarray(ptr, ptr + bytes), { at: offset });
      if (actual !== bytes) {
        postLog(`BROWSER_BLOCK_READ result=fail id=${id} offset=${offset} bytes=${bytes} actual=${actual}`);
        return -1;
      }
    } else {
      block.device.readInto(heap().subarray(ptr, ptr + bytes), offset);
    }
    postLog(`BROWSER_BLOCK_READ result=pass id=${id} asset=${block.key} backend=${block.backend} offset=${offset} bytes=${bytes}`);
    return 0;
  };

  moduleArg.xemuBrowserBlockWrite = (id, offset, ptr, bytes) => {
    const block = registry.byId.get(id);
    offset = Number(offset);
    if (!block || offset < 0 || bytes < 0 || offset + bytes > block.size) {
      postLog(`BROWSER_BLOCK_WRITE result=fail id=${id} offset=${offset} bytes=${bytes}`);
      return -1;
    }
    if (block.accessHandle) {
      const actual = block.accessHandle.write(heap().subarray(ptr, ptr + bytes), { at: offset });
      if (actual !== bytes) {
        postLog(`BROWSER_BLOCK_WRITE result=fail id=${id} offset=${offset} bytes=${bytes} actual=${actual}`);
        return -1;
      }
    } else {
      block.device.writeFrom(heap().subarray(ptr, ptr + bytes), offset);
    }
    postLog(`BROWSER_BLOCK_WRITE result=pass id=${id} asset=${block.key} backend=${block.backend} offset=${offset} bytes=${bytes}`);
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
        postLog(`BROWSER_BLOCK_SNAPSHOT result=pass id=${id} asset=${block.key} backend=${block.backend} chunks=${snapshot.chunks.length} serialized_bytes=${serialized.length}`);
        void persistBlockSnapshot(block, snapshot, serialized.length);
      } else {
        postLog(`BROWSER_BLOCK_SNAPSHOT result=skip id=${id} asset=${block.key} backend=${block.backend} reason=no-dirty-chunks`);
      }
    }
    postLog(`BROWSER_BLOCK_FLUSH result=${block ? "pass" : "fail"} id=${id}`);
    return block ? 0 : -1;
  };

  moduleArg.xemuBrowserBlockClose = (id) => {
    const block = registry.byId.get(id);
    if (block && block.accessHandle) {
      block.accessHandle.close();
    }
    registry.byId.delete(id);
    postLog(`BROWSER_BLOCK_CLOSE result=${block ? "pass" : "skip"} id=${id}`);
  };

  globalThis.xemuBrowserBlockOpen = moduleArg.xemuBrowserBlockOpen;
  globalThis.xemuBrowserBlockGetSize = moduleArg.xemuBrowserBlockGetSize;
  globalThis.xemuBrowserBlockRead = moduleArg.xemuBrowserBlockRead;
  globalThis.xemuBrowserBlockWrite = moduleArg.xemuBrowserBlockWrite;
  globalThis.xemuBrowserBlockFlush = moduleArg.xemuBrowserBlockFlush;
  globalThis.xemuBrowserBlockClose = moduleArg.xemuBrowserBlockClose;
}

function installBrowserDisplayCallbacks(moduleArg) {
  const heap = () => globalThis.xemuBrowserDisplayHeap || moduleArg.HEAPU8;

  moduleArg.xemuBrowserDisplayFrame = (frameId, width, height, stride, bpp, format, ptr, bytes) => {
    frameId = Number(frameId);
    width = Number(width);
    height = Number(height);
    stride = Number(stride);
    bpp = Number(bpp);
    format = Number(format);
    ptr = Number(ptr);
    bytes = Number(bytes);

    if (width <= 0 || height <= 0 || stride <= 0 || bpp <= 0 || ptr <= 0 || bytes <= 0) {
      postLog([
        "BROWSER_DISPLAY_FRAME",
        "result=fail",
        "reason=bad-geometry",
        `frame=${frameId}`,
        `width=${width}`,
        `height=${height}`,
        `stride=${stride}`,
        `bpp=${bpp}`,
        `bytes=${bytes}`,
      ].join(" "));
      return 0;
    }

    const source = heap().subarray(ptr, ptr + bytes);
    const copy = source.slice();
    self.postMessage({
      type: "displayFrame",
      frame: {
        frameId,
        width,
        height,
        stride,
        bpp,
        format,
        buffer: copy.buffer,
      },
    }, [copy.buffer]);
    postLog([
      "BROWSER_DISPLAY_FRAME",
      "result=pass",
      "source=browser-framebuffer",
      `frame=${frameId}`,
      `width=${width}`,
      `height=${height}`,
      `stride=${stride}`,
      `bpp=${bpp}`,
      `format=${format}`,
      `bytes=${bytes}`,
    ].join(" "));
    return 1;
  };

  globalThis.xemuBrowserDisplayFrame = moduleArg.xemuBrowserDisplayFrame;
}

async function runBoot({ buildDir, timeoutMs, assets, pcrtcVblankMode = "", browserIcount = "", traceOptions = {} }) {
  const validationError = validateAssets(assets);
  const hasRealHdd = assets.some((asset) => asset.key === "hdd");
  if (validationError) {
    postLog(`BROWSER_ASSET_VALIDATE result=fail reason=${validationError}`);
    self.postMessage({ type: "done", result: "invalid-assets" });
    return;
  }
  postLog(`BROWSER_ASSET_VALIDATE result=pass count=${assets.length}`);
  await probeBlockAssets(assets);
  const browserBlocks = await prepareBrowserBlocks(assets);
  const materializedAssets = await materializeAssets(assets);

  const moduleUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.js`, self.location.href).href;
  const wasmUrl = new URL(`${buildDir.replace(/\/$/, "")}/qemu-system-i386.wasm`, self.location.href).href;
  const { default: Factory } = await import(moduleUrl);
  const startedAt = Date.now();
  let moduleFS = null;
  let eepromPath = eepromPathForAssets(assets);

  const timeout = setTimeout(() => {
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, "timeout");
    }
    postLog(`BOOT_SMOKE_RESULT reason=browser-host-timeout elapsed_ms=${Date.now() - startedAt} exit=124`);
    self.postMessage({ type: "done", result: "timeout" });
  }, timeoutMs);

  const qemuArgs = [
    "-config_path", "/xemu-fixtures/xemu-smoke.toml",
    "-headless_boot_ms", String(timeoutMs),
  ];
  const browserIcountText = String(browserIcount || "").trim();
  if (browserIcountText) {
    qemuArgs.push("-icount", browserIcountText);
    postLog(`BROWSER_DIAGNOSTIC_APPLY name=browser_icount value=${browserIcountText} target=argv:-icount`);
  }

  const moduleArg = {
    locateFile(path) {
      if (path.endsWith(".wasm")) {
        return wasmUrl;
      }
      return new URL(`${buildDir.replace(/\/$/, "")}/${path}`, self.location.href).href;
    },
    arguments: qemuArgs,
    print: postLog,
    printErr: postLog,
  };
  installBrowserBlockCallbacks(moduleArg, browserBlocks);
  installBrowserDisplayCallbacks(moduleArg);

  moduleArg.preRun = [() => {
    moduleFS = moduleArg.FS;
    writeFixtureFiles(moduleArg.FS, materializedAssets);
    moduleArg.FS.writeFile("/xemu-fixtures/boot_trace_context.txt", "browser-runtime\n");
    if (pcrtcVblankMode) {
      moduleArg.FS.writeFile("/xemu-fixtures/pcrtc_vblank_mode.txt", `${pcrtcVblankMode}\n`);
      postLog(`BROWSER_DIAGNOSTIC_APPLY name=pcrtc_vblank_mode value=${pcrtcVblankMode} target=/xemu-fixtures/pcrtc_vblank_mode.txt`);
    }
    writeTraceOptions(moduleArg.FS, traceOptions);
    moduleArg.FS.writeFile("/xemu-fixtures/xemu-smoke.toml", makeConfig(materializedAssets));
  }];

  try {
    await Factory(moduleArg);
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, "module-return");
    }
    if (hasRealHdd) {
      postLog(`BROWSER_MODULE_RETURN result=deferred reason=real-hdd elapsed_ms=${Date.now() - startedAt}`);
      return;
    }
    clearTimeout(timeout);
    postLog(`BOOT_SMOKE_RESULT reason=browser-module-return elapsed_ms=${Date.now() - startedAt} exit=0`);
    self.postMessage({ type: "done", result: "pass" });
  } catch (error) {
    clearTimeout(timeout);
    if (moduleFS) {
      emitEeprom(moduleFS, eepromPath, "error");
    }
    postLog(`BROWSER_BOOT_ERROR ${error && error.stack ? error.stack : error}`);
    self.postMessage({ type: "done", result: "fail" });
  }
}

self.onmessage = (event) => {
  if (!event.data || event.data.type !== "start") {
    return;
  }
  runBoot(event.data).catch((error) => {
    postLog(`BROWSER_BOOT_ERROR ${error && error.stack ? error.stack : error}`);
    self.postMessage({ type: "done", result: "fail" });
  });
};
