const refs = {
  capabilities: document.getElementById("capabilities"),
  startBtn: document.getElementById("startBtn"),
  syntheticBtn: document.getElementById("syntheticBtn"),
  stopBtn: document.getElementById("stopBtn"),
  downloadBtn: document.getElementById("downloadBtn"),
  smokeTestInput: document.getElementById("smokeTestInput"),
  timeoutInput: document.getElementById("timeoutInput"),
  buildDirInput: document.getElementById("buildDirInput"),
  logOutput: document.getElementById("logOutput"),
  buildLabel: document.getElementById("buildLabel"),
  displayCanvas: document.getElementById("displayCanvas"),
  captureDisplayBtn: document.getElementById("captureDisplayBtn"),
};

const assets = [
  { key: "flash", label: "Flash", input: document.getElementById("flashInput"), status: document.getElementById("flashStatus"), required: true },
  { key: "mcpx", label: "MCPX", input: document.getElementById("mcpxInput"), status: document.getElementById("mcpxStatus"), exactSize: 512 },
  { key: "eeprom", label: "EEPROM", input: document.getElementById("eepromInput"), status: document.getElementById("eepromStatus"), exactSize: 256 },
  { key: "hdd", label: "HDD", input: document.getElementById("hddInput"), status: document.getElementById("hddStatus") },
  { key: "dvd", label: "DVD", input: document.getElementById("dvdInput"), status: document.getElementById("dvdStatus") },
];

const configStorageKey = "xemu.browserBoot.config.v1";
const eepromStorageKey = "xemu.browserBoot.eeprom.v1";
const localAssetManifestUrl = "/__xemu_assets__/manifest.json";
const defaultBuildDir = "../../build-wasm";

let worker = null;
let transcript = [];
let lastObjectUrl = null;
let runTimer = null;
let localAssets = new Map();
let localAssetManifestPromise = null;
let displayFrameCount = 0;
let displayHasSeenNonblack = false;
let displaySkippedBlackFrameCount = 0;

function loadConfig() {
  try {
    const config = JSON.parse(localStorage.getItem(configStorageKey) || "{}");
    if (typeof config.timeoutMs === "number") {
      refs.timeoutInput.value = String(config.timeoutMs);
    }
    if (typeof config.smokeTest === "boolean") {
      refs.smokeTestInput.checked = config.smokeTest;
    }
    if (typeof config.buildDir === "string" && config.buildDir) {
      refs.buildDirInput.value = config.buildDir.includes("build-wasm-pic")
        ? defaultBuildDir
        : config.buildDir;
    }
    saveConfig();
  } catch {
    localStorage.removeItem(configStorageKey);
  }
}

function currentConfig() {
  return {
    timeoutMs: Math.max(100, Number(refs.timeoutInput.value) || 3000),
    buildDir: refs.buildDirInput.value.trim() || defaultBuildDir,
    smokeTest: refs.smokeTestInput.checked,
  };
}

function updateBuildLabel() {
  refs.buildLabel.textContent = `${currentConfig().buildDir}/qemu-system-i386.js`;
}

function updateRunModeControls() {
  refs.timeoutInput.disabled = !refs.smokeTestInput.checked;
}

function saveConfig() {
  updateRunModeControls();
  localStorage.setItem(configStorageKey, JSON.stringify(currentConfig()));
  updateBuildLabel();
}

function arrayBufferToBase64(buffer) {
  let binary = "";
  const bytes = new Uint8Array(buffer);
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToArrayBuffer(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function loadPersistedEepromAsset() {
  const base64 = localStorage.getItem(eepromStorageKey);
  if (!base64) {
    return null;
  }
  const buffer = base64ToArrayBuffer(base64);
  if (buffer.byteLength !== 256) {
    localStorage.removeItem(eepromStorageKey);
    return null;
  }
  return {
    key: "eeprom",
    name: "persisted-eeprom.bin",
    size: 256,
    buffer,
    persisted: true,
  };
}

function savePersistedEeprom(base64) {
  const buffer = base64ToArrayBuffer(base64);
  if (buffer.byteLength !== 256) {
    return;
  }
  localStorage.setItem(eepromStorageKey, arrayBufferToBase64(buffer));
}

function capabilityRows() {
  return [
    ["crossOriginIsolated", globalThis.crossOriginIsolated === true],
    ["SharedArrayBuffer", typeof SharedArrayBuffer === "function"],
    ["Worker", typeof Worker === "function"],
    ["BigInt", typeof BigInt === "function"],
    ["WebAssembly", typeof WebAssembly === "object"],
  ];
}

function renderCapabilities() {
  refs.capabilities.replaceChildren(...capabilityRows().map(([name, ok]) => {
    const item = document.createElement("div");
    item.className = "status-pill";
    const label = document.createElement("span");
    label.textContent = name;
    const value = document.createElement("span");
    value.className = ok ? "ok" : "bad";
    value.textContent = ok ? "yes" : "no";
    item.append(label, value);
    return item;
  }));
}

function appendLog(line) {
  const text = String(line);
  transcript.push(text);
  refs.logOutput.textContent += `${text}\n`;
  refs.logOutput.scrollTop = refs.logOutput.scrollHeight;
  refs.downloadBtn.disabled = transcript.length === 0;
}

function clearDisplayCanvas() {
  const canvas = refs.displayCanvas;
  const context = canvas.getContext("2d", { alpha: false });
  context.fillStyle = "#000";
  context.fillRect(0, 0, canvas.width, canvas.height);
}

function pixelsHaveNonblack(data) {
  for (let offset = 0; offset < data.length; offset += 4) {
    if (data[offset] !== 0 || data[offset + 1] !== 0 || data[offset + 2] !== 0) {
      return true;
    }
  }
  return false;
}

function drawDisplayFrame({ width, height, source = "unknown", pixels, nonblack = null }) {
  const canvas = refs.displayCanvas;
  const data = new Uint8ClampedArray(pixels);
  const frameHasNonblack = nonblack === true || pixelsHaveNonblack(data);

  displayFrameCount += 1;

  if (displayHasSeenNonblack && !frameHasNonblack) {
    displaySkippedBlackFrameCount += 1;
    if (displaySkippedBlackFrameCount === 1 ||
        displaySkippedBlackFrameCount % 300 === 0) {
      appendLog(`BROWSER_DISPLAY_FRAME result=skip-black frame=${displayFrameCount} source=${source} width=${width} height=${height} skipped=${displaySkippedBlackFrameCount}`);
    }
    return;
  }

  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  const context = canvas.getContext("2d", { alpha: false });
  const image = new ImageData(data, width, height);
  context.putImageData(image, 0, 0);
  const firstNonblack = frameHasNonblack && !displayHasSeenNonblack;
  displayHasSeenNonblack ||= frameHasNonblack;
  if (displayFrameCount === 1 || firstNonblack || displayFrameCount % 300 === 0) {
    appendLog(`BROWSER_DISPLAY_FRAME result=pass frame=${displayFrameCount} source=${source} width=${width} height=${height} nonblack=${frameHasNonblack ? "yes" : "no"}`);
  }
}

function createGlCanvasTransfer() {
  if (typeof OffscreenCanvas !== "function") {
    appendLog("WebGL worker canvas unavailable: OffscreenCanvas is not supported.");
    return null;
  }

  const offscreen = new OffscreenCanvas(640, 480);
  offscreen.id = "canvas";
  return offscreen;
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function captureSyntheticDisplayEvidence({ log = true } = {}) {
  const canvas = refs.displayCanvas;
  const context = canvas.getContext("2d", { alpha: false });
  const image = context.getImageData(0, 0, canvas.width, canvas.height);
  let nonempty = false;

  for (let offset = 0; offset < image.data.length; offset += 4) {
    if (image.data[offset] !== 0 || image.data[offset + 1] !== 0 || image.data[offset + 2] !== 0) {
      nonempty = true;
      break;
    }
  }

  const hash = await sha256Hex(image.data);

  return { hash, nonempty, width: canvas.width, height: canvas.height };
}

function setAssetStatus(asset, text, state = "") {
  asset.status.textContent = text;
  asset.status.className = state;
}

function setAssetPickerLabel(asset, text, hasAuto = false) {
  const row = asset.input.closest(".asset-row");
  const label = row.querySelector(".file-control-label");
  label.textContent = text;
  row.classList.toggle("has-auto", hasAuto);
}

function formatBytes(size) {
  if (size < 1024) {
    return `${size} B`;
  }
  if (size < 1024 * 1024) {
    return `${(size / 1024).toFixed(1)} KiB`;
  }
  return `${(size / (1024 * 1024)).toFixed(1)} MiB`;
}

async function loadLocalAssetManifest() {
  if (localAssetManifestPromise) {
    return localAssetManifestPromise;
  }

  localAssetManifestPromise = fetch(localAssetManifestUrl, { cache: "no-store" })
    .then(async (response) => {
      if (!response.ok) {
        throw new Error(`manifest status ${response.status}`);
      }
      const manifest = await response.json();
      localAssets = new Map();
      for (const asset of manifest.assets || []) {
        if (asset && asset.key && asset.available && asset.url) {
          localAssets.set(asset.key, asset);
        }
      }
      validateAssets();
      return localAssets;
    })
    .catch((error) => {
      localAssets = new Map();
      validateAssets();
      return localAssets;
    });

  return localAssetManifestPromise;
}

function localAssetFor(key) {
  return localAssets.get(key) || null;
}

function validateAssets() {
  let ok = true;

  for (const asset of assets) {
    const file = asset.input.files[0] || null;
    const localAsset = file ? null : localAssetFor(asset.key);
    const required = asset.required;

    if (!file) {
      if (localAsset) {
        setAssetPickerLabel(asset, `Using ${localAsset.name || `${asset.key}.bin`}`, true);
        if (asset.exactSize && localAsset.size !== asset.exactSize) {
          setAssetStatus(asset, `auto ${localAsset.size} B`, "bad");
          ok = false;
        } else {
          setAssetStatus(asset, `auto ${formatBytes(localAsset.size)}`, "ok");
        }
        continue;
      }
      setAssetPickerLabel(asset, "Choose file...");
      setAssetStatus(asset, required ? "required" : asset.key === "eeprom" ? "generated" : "optional", required ? "bad" : "");
      ok = ok && !required;
      continue;
    }

    setAssetPickerLabel(asset, file.name);
    if (asset.exactSize && file.size !== asset.exactSize) {
      setAssetStatus(asset, `${file.size} B`, "bad");
      ok = false;
      continue;
    }

    setAssetStatus(asset, formatBytes(file.size), "ok");
  }

  refs.startBtn.disabled = !ok || worker !== null;
  refs.syntheticBtn.disabled = worker !== null;
  return ok;
}

async function fileToTransfer(asset) {
  const file = asset.input.files[0] || null;
  if (!file) {
    return null;
  }
  if (asset.key === "hdd" || asset.key === "dvd") {
    return {
      key: asset.key,
      name: file.name,
      size: file.size,
      source: "file-picker",
      blob: file,
    };
  }
  return {
    key: asset.key,
    name: file.name,
    size: file.size,
    source: "file-picker",
    buffer: await file.arrayBuffer(),
  };
}

async function localAssetToTransfer(asset) {
  const localAsset = localAssetFor(asset.key);
  if (!localAsset) {
    return null;
  }

  const response = await fetch(localAsset.url, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`local asset ${asset.key} status ${response.status}`);
  }

  const blob = await response.blob();
  const selected = {
    key: asset.key,
    name: localAsset.name || `${asset.key}.bin`,
    size: localAsset.size || blob.size,
    source: "local-server",
  };

  if (asset.key === "hdd" || asset.key === "dvd") {
    return {
      ...selected,
      blob,
    };
  }

  return {
    ...selected,
    buffer: await blob.arrayBuffer(),
  };
}

async function assetToTransfer(asset) {
  return (await fileToTransfer(asset)) || (await localAssetToTransfer(asset));
}

async function runWithAssets(selectedAssets, runMode) {
  const { buildDir, timeoutMs, smokeTest } = currentConfig();
  const startedAt = Date.now();
  saveConfig();
  refs.logOutput.textContent = "";
  transcript = [];
  displayFrameCount = 0;
  displayHasSeenNonblack = false;
  displaySkippedBlackFrameCount = 0;
  clearDisplayCanvas();

  worker = new Worker("./worker.js", { type: "module" });
  refs.startBtn.disabled = true;
  refs.syntheticBtn.disabled = true;
  refs.stopBtn.disabled = false;

  worker.onmessage = (event) => {
    const { type, result, base64, message } = event.data || {};
    if (type === "eeprom") {
      savePersistedEeprom(base64);
    } else if (type === "display-frame") {
      drawDisplayFrame(event.data);
    } else if (type === "log") {
      appendLog(message || "");
    } else if (type === "error") {
      appendLog(`Error: ${message || "unknown worker error"}`);
    } else if (type === "done") {
      appendLog(`Run finished: ${result || "done"}`);
      stopWorker(false);
    }
  };

  worker.onerror = (event) => {
    appendLog(`Error: ${event.message}`);
    stopWorker(false);
  };

  if (smokeTest) {
    runTimer = setTimeout(() => {
      runTimer = null;
      if (!worker) {
        return;
      }
      stopWorker(false);
      appendLog(`Run timed out after ${Date.now() - startedAt} ms.`);
    }, timeoutMs);
  } else {
    appendLog("Interactive run started.");
  }

  const glCanvas = createGlCanvasTransfer();
  const transferList = selectedAssets
    .filter((asset) => asset.buffer)
    .map((asset) => asset.buffer);
  if (glCanvas) {
    transferList.push(glCanvas);
  }

  worker.postMessage({
    type: "start",
    buildDir,
    timeoutMs,
    smokeTest,
    assets: selectedAssets,
    canvas: glCanvas,
  }, transferList);
}

async function startRun() {
  try {
    await loadLocalAssetManifest();
    if (!validateAssets()) {
      appendLog("Invalid assets.");
      return;
    }

    const selectedAssets = [];
    for (const asset of assets) {
      const selected = await assetToTransfer(asset);
      if (selected) {
        selectedAssets.push(selected);
      }
    }
    if (!selectedAssets.some((asset) => asset.key === "eeprom")) {
      const persistedEeprom = loadPersistedEepromAsset();
      if (persistedEeprom) {
        selectedAssets.push(persistedEeprom);
      }
    }

    await runWithAssets(selectedAssets, "selected-assets");
  } catch (error) {
    appendLog(`Error: ${error.message || String(error)}`);
    validateAssets();
  }
}

async function startSyntheticRun() {
  try {
    await loadLocalAssetManifest();
    const flashBytes = 1024 * 1024;
    const localFlash = await localAssetToTransfer(assets.find((asset) => asset.key === "flash"));
    const selectedAssets = [localFlash || {
      key: "flash",
      name: "synthetic-zero-flash.bin",
      size: flashBytes,
      source: "synthetic",
      buffer: new ArrayBuffer(flashBytes),
    }];
    const persistedEeprom = loadPersistedEepromAsset();
    if (persistedEeprom) {
      selectedAssets.push(persistedEeprom);
    }

    await runWithAssets(selectedAssets, "synthetic-zero-flash");
  } catch (error) {
    appendLog(`Error: ${error.message || String(error)}`);
    validateAssets();
  }
}

function stopWorker(report = true) {
  if (runTimer) {
    clearTimeout(runTimer);
    runTimer = null;
  }
  if (worker) {
    worker.terminate();
    worker = null;
  }
  refs.stopBtn.disabled = true;
  validateAssets();
  if (report) {
    appendLog("Run stopped.");
  }
}

function downloadTranscript() {
  if (lastObjectUrl) {
    URL.revokeObjectURL(lastObjectUrl);
  }
  const blob = new Blob([transcript.join("\n"), "\n"], { type: "text/plain" });
  lastObjectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = lastObjectUrl;
  link.download = `xemu-browser-boot-${new Date().toISOString().replace(/[:.]/g, "-")}.log`;
  link.click();
}

for (const asset of assets) {
  asset.input.addEventListener("change", validateAssets);
}

refs.smokeTestInput.addEventListener("change", saveConfig);
refs.timeoutInput.addEventListener("change", saveConfig);
refs.buildDirInput.addEventListener("change", saveConfig);
refs.startBtn.addEventListener("click", startRun);
refs.syntheticBtn.addEventListener("click", startSyntheticRun);
refs.stopBtn.addEventListener("click", () => stopWorker(true));
refs.downloadBtn.addEventListener("click", downloadTranscript);
refs.captureDisplayBtn.addEventListener("click", () => {
  captureSyntheticDisplayEvidence().catch((error) => {
    appendLog(`Error: ${error.message}`);
  });
});

loadConfig();
renderCapabilities();
clearDisplayCanvas();
globalThis.xemuBrowserDisplayCapture = captureSyntheticDisplayEvidence;
validateAssets();
loadLocalAssetManifest();
