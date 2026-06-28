const refs = {
  capabilities: document.getElementById("capabilities"),
  startBtn: document.getElementById("startBtn"),
  syntheticBtn: document.getElementById("syntheticBtn"),
  stopBtn: document.getElementById("stopBtn"),
  downloadBtn: document.getElementById("downloadBtn"),
  timeoutInput: document.getElementById("timeoutInput"),
  buildDirInput: document.getElementById("buildDirInput"),
  requireHddInput: document.getElementById("requireHddInput"),
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

let worker = null;
let transcript = [];
let lastObjectUrl = null;
let runTimer = null;

function loadConfig() {
  try {
    const config = JSON.parse(localStorage.getItem(configStorageKey) || "{}");
    if (typeof config.timeoutMs === "number") {
      refs.timeoutInput.value = String(config.timeoutMs);
    }
    if (typeof config.buildDir === "string" && config.buildDir) {
      refs.buildDirInput.value = config.buildDir;
    }
    if (typeof config.requireHdd === "boolean") {
      refs.requireHddInput.checked = config.requireHdd;
    }
  } catch {
    localStorage.removeItem(configStorageKey);
  }
}

function currentConfig() {
  return {
    timeoutMs: Math.max(100, Number(refs.timeoutInput.value) || 3000),
    buildDir: refs.buildDirInput.value.trim() || "../../build-wasm-pic",
    requireHdd: refs.requireHddInput.checked,
  };
}

function saveConfig() {
  localStorage.setItem(configStorageKey, JSON.stringify(currentConfig()));
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
    appendLog(`BROWSER_EEPROM_PERSIST result=discarded reason=bad-size size=${buffer.byteLength}`);
    return null;
  }
  appendLog("BROWSER_EEPROM_PERSIST result=loaded bytes=256 source=localStorage");
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
    appendLog(`BROWSER_EEPROM_PERSIST result=skip reason=bad-size size=${buffer.byteLength}`);
    return;
  }
  localStorage.setItem(eepromStorageKey, arrayBufferToBase64(buffer));
  appendLog("BROWSER_EEPROM_PERSIST result=saved bytes=256 target=localStorage");
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

function drawSyntheticFramebuffer() {
  const canvas = refs.displayCanvas;
  const context = canvas.getContext("2d", { alpha: false });
  const image = context.createImageData(canvas.width, canvas.height);
  const data = image.data;

  for (let y = 0; y < canvas.height; y++) {
    for (let x = 0; x < canvas.width; x++) {
      const offset = (y * canvas.width + x) * 4;
      const checker = ((x >> 4) ^ (y >> 4)) & 1;
      data[offset] = (x * 5 + y * 3 + (checker ? 79 : 13)) & 0xff;
      data[offset + 1] = (x * 2 + y * 7 + (checker ? 29 : 101)) & 0xff;
      data[offset + 2] = (x * 11 + y + (checker ? 151 : 47)) & 0xff;
      data[offset + 3] = 0xff;
    }
  }

  context.putImageData(image, 0, 0);
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
  const marker = "BOOT_MARK b4 display=visible source=synthetic-framebuffer";
  const capture = [
    "BROWSER_DISPLAY_CAPTURE",
    `result=${nonempty ? "pass" : "fail"}`,
    `nonempty=${nonempty ? "yes" : "no"}`,
    `hash=${hash}`,
    "source=synthetic-framebuffer",
    `width=${canvas.width}`,
    `height=${canvas.height}`,
  ].join(" ");

  if (log) {
    appendLog(marker);
    appendLog(capture);
  }

  return { marker, capture, hash, nonempty, width: canvas.width, height: canvas.height };
}

function logBrowserMetadata(buildDir, timeoutMs) {
  appendLog(`BROWSER_BOOT_START timeout_ms=${timeoutMs} build_dir=${buildDir}`);
  appendLog(`BROWSER_CONFIG persisted=yes require_hdd=${refs.requireHddInput.checked ? "yes" : "no"}`);
  appendLog(`BROWSER_USER_AGENT value=${JSON.stringify(navigator.userAgent)}`);
  appendLog(`BROWSER_LOCATION href=${JSON.stringify(location.href)}`);
  for (const [name, ok] of capabilityRows()) {
    appendLog(`BROWSER_CAPABILITY name=${name} available=${ok ? "yes" : "no"}`);
  }
}

async function logArtifactMetadata(buildDir) {
  const base = buildDir.replace(/\/$/, "");
  const artifacts = [
    ["js", `${base}/qemu-system-i386.js`],
    ["wasm", `${base}/qemu-system-i386.wasm`],
  ];

  for (const [kind, artifactPath] of artifacts) {
    const url = new URL(artifactPath, location.href).href;
    try {
      const response = await fetch(url, { method: "HEAD", cache: "no-store" });
      appendLog([
        "BROWSER_ARTIFACT",
        `kind=${kind}`,
        `url=${JSON.stringify(url)}`,
        `status=${response.status}`,
        `bytes=${response.headers.get("content-length") || "unknown"}`,
        `type=${JSON.stringify(response.headers.get("content-type") || "")}`,
      ].join(" "));
    } catch (error) {
      appendLog(`BROWSER_ARTIFACT kind=${kind} url=${JSON.stringify(url)} status=error message=${JSON.stringify(error.message)}`);
    }
  }
}

function setAssetStatus(asset, text, state = "") {
  asset.status.textContent = text;
  asset.status.className = state;
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

function validateAssets() {
  let ok = true;
  const requireHdd = refs.requireHddInput.checked;

  for (const asset of assets) {
    const file = asset.input.files[0] || null;
    const required = asset.required || (requireHdd && asset.key === "hdd");

    if (!file) {
      setAssetStatus(asset, required ? "required" : asset.key === "eeprom" ? "generated" : "optional", required ? "bad" : "");
      ok = ok && !required;
      continue;
    }

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
      blob: file,
    };
  }
  return {
    key: asset.key,
    name: file.name,
    size: file.size,
    buffer: await file.arrayBuffer(),
  };
}

async function runWithAssets(selectedAssets, runMode) {
  const { buildDir, timeoutMs } = currentConfig();
  const startedAt = Date.now();
  saveConfig();
  refs.buildLabel.textContent = `${buildDir}/qemu-system-i386.js`;
  refs.logOutput.textContent = "";
  transcript = [];
  logBrowserMetadata(buildDir, timeoutMs);
  appendLog(`BROWSER_RUN_MODE mode=${runMode}`);
  await logArtifactMetadata(buildDir);

  for (const selected of selectedAssets) {
    appendLog(`BROWSER_ASSET name=${selected.key} file=${selected.name} size=${selected.size}`);
  }

  worker = new Worker("./worker.js", { type: "module" });
  refs.startBtn.disabled = true;
  refs.syntheticBtn.disabled = true;
  refs.stopBtn.disabled = false;

  worker.onmessage = (event) => {
    const { type, line, result, base64 } = event.data || {};
    if (type === "log") {
      appendLog(line);
    } else if (type === "eeprom") {
      savePersistedEeprom(base64);
    } else if (type === "done") {
      appendLog(`BROWSER_BOOT_RESULT result=${result || "done"}`);
      stopWorker(false);
    }
  };

  worker.onerror = (event) => {
    appendLog(`BROWSER_BOOT_RESULT result=fail reason=worker-error message=${event.message}`);
    stopWorker(false);
  };

  runTimer = setTimeout(() => {
    runTimer = null;
    if (!worker) {
      return;
    }
    appendLog(`BOOT_SMOKE_RESULT reason=browser-main-timeout elapsed_ms=${Date.now() - startedAt} exit=124`);
    stopWorker(false);
    appendLog("BROWSER_BOOT_RESULT result=timeout");
  }, timeoutMs);

  worker.postMessage({
    type: "start",
    buildDir,
    timeoutMs,
    assets: selectedAssets,
  }, selectedAssets.filter((asset) => asset.buffer).map((asset) => asset.buffer));
}

async function startRun() {
  if (!validateAssets()) {
    appendLog("BROWSER_BOOT_RESULT result=fail reason=invalid-assets");
    return;
  }

  const selectedAssets = [];
  for (const asset of assets) {
    const selected = await fileToTransfer(asset);
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
}

async function startSyntheticRun() {
  const flashBytes = 1024 * 1024;
  const selectedAssets = [{
    key: "flash",
    name: "synthetic-zero-flash.bin",
    size: flashBytes,
    buffer: new ArrayBuffer(flashBytes),
  }];
  const persistedEeprom = loadPersistedEepromAsset();
  if (persistedEeprom) {
    selectedAssets.push(persistedEeprom);
  }

  await runWithAssets(selectedAssets, "synthetic-zero-flash");
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
    appendLog("BROWSER_BOOT_RESULT result=stopped");
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

refs.requireHddInput.addEventListener("change", validateAssets);
refs.timeoutInput.addEventListener("change", saveConfig);
refs.buildDirInput.addEventListener("change", saveConfig);
refs.requireHddInput.addEventListener("change", saveConfig);
refs.startBtn.addEventListener("click", startRun);
refs.syntheticBtn.addEventListener("click", startSyntheticRun);
refs.stopBtn.addEventListener("click", () => stopWorker(true));
refs.downloadBtn.addEventListener("click", downloadTranscript);
refs.captureDisplayBtn.addEventListener("click", () => {
  captureSyntheticDisplayEvidence().catch((error) => {
    appendLog(`BROWSER_DISPLAY_CAPTURE result=fail reason=${JSON.stringify(error.message)}`);
  });
});

loadConfig();
renderCapabilities();
drawSyntheticFramebuffer();
globalThis.xemuBrowserDisplayCapture = captureSyntheticDisplayEvidence;
validateAssets();
