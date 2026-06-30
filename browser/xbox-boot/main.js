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
let displaySource = "synthetic-framebuffer";
let displayFrame = null;
let autoLoadingAssets = false;

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
  displaySource = "synthetic-framebuffer";
  displayFrame = null;
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function frameToImageData(context, frame) {
  const { width, height, stride, bpp } = frame;
  const raw = new Uint8Array(frame.buffer);
  const rgba = new Uint8ClampedArray(width * height * 4);

  if (bpp === 32) {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const source = y * stride + x * 4;
        const target = (y * width + x) * 4;
        rgba[target] = raw[source + 2] || 0;
        rgba[target + 1] = raw[source + 1] || 0;
        rgba[target + 2] = raw[source] || 0;
        rgba[target + 3] = 0xff;
      }
    }
  } else if (bpp === 24) {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const source = y * stride + x * 3;
        const target = (y * width + x) * 4;
        rgba[target] = raw[source + 2] || 0;
        rgba[target + 1] = raw[source + 1] || 0;
        rgba[target + 2] = raw[source] || 0;
        rgba[target + 3] = 0xff;
      }
    }
  } else if (bpp === 16) {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const source = y * stride + x * 2;
        const target = (y * width + x) * 4;
        const value = (raw[source] || 0) | ((raw[source + 1] || 0) << 8);
        const x1r5g5b5 = frame.format === 1 || frame.format === 2;
        rgba[target] = ((value >> (x1r5g5b5 ? 10 : 11)) & 0x1f) * 255 / 31;
        rgba[target + 1] = ((value >> 5) & (x1r5g5b5 ? 0x1f : 0x3f)) * 255 / (x1r5g5b5 ? 31 : 63);
        rgba[target + 2] = (value & 0x1f) * 255 / 31;
        rgba[target + 3] = 0xff;
      }
    }
  } else {
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const source = y * stride + x;
        const target = (y * width + x) * 4;
        const value = raw[source] || 0;
        rgba[target] = value;
        rgba[target + 1] = value;
        rgba[target + 2] = value;
        rgba[target + 3] = 0xff;
      }
    }
  }

  return new ImageData(rgba, width, height);
}

async function drawBrowserDisplayFrame(frame) {
  const canvas = refs.displayCanvas;
  const context = canvas.getContext("2d", { alpha: false });
  if (canvas.width !== frame.width || canvas.height !== frame.height) {
    canvas.width = frame.width;
    canvas.height = frame.height;
    canvas.style.aspectRatio = `${frame.width} / ${frame.height}`;
  }
  context.putImageData(frameToImageData(context, frame), 0, 0);
  displaySource = "browser-framebuffer";
  displayFrame = frame;
  await captureDisplayEvidence({ log: true });
}

async function captureDisplayEvidence({ log = true } = {}) {
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
  const marker = [
    "BOOT_MARK b4 display=visible",
    `source=${displaySource}`,
    displayFrame ? `frame=${displayFrame.frameId}` : "",
    `width=${canvas.width}`,
    `height=${canvas.height}`,
  ].filter(Boolean).join(" ");
  const capture = [
    "BROWSER_DISPLAY_CAPTURE",
    `result=${nonempty ? "pass" : "fail"}`,
    `nonempty=${nonempty ? "yes" : "no"}`,
    `hash=${hash}`,
    `source=${displaySource}`,
    `width=${canvas.width}`,
    `height=${canvas.height}`,
  ].join(" ");

  if (log && nonempty) {
    appendLog(marker);
  }
  if (log) {
    appendLog(capture);
  }

  return {
    marker,
    capture,
    hash,
    nonempty,
    source: displaySource,
    frameId: displayFrame ? displayFrame.frameId : null,
    width: canvas.width,
    height: canvas.height,
  };
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
    const file = asset.input.files[0] || asset.serverFile || null;
    const required = asset.required || (requireHdd && asset.key === "hdd");

    if (!file) {
      const text = autoLoadingAssets ? "loading" :
        required ? "required" : asset.key === "eeprom" ? "generated" : "optional";
      setAssetStatus(asset, text, required || autoLoadingAssets ? "bad" : "");
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
  const file = asset.input.files[0] || asset.serverFile || null;
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

function assignFileInput(asset, file) {
  asset.serverFile = file;

  try {
    const dataTransfer = new DataTransfer();
    dataTransfer.items.add(file);
    asset.input.files = dataTransfer.files;
  } catch {
    /* Some browsers do not allow assigning input.files. serverFile is enough. */
  }
}

async function loadServerAsset(asset) {
  const response = await fetch(`/__xemu_smoke_asset/${asset.key}`, {
    cache: "no-store",
  });

  if (!response.ok) {
    return false;
  }

  const filename = response.headers.get("X-Xemu-Asset-Filename") ||
    `${asset.key}.bin`;
  const blob = await response.blob();
  const file = new File([blob], filename, {
    type: response.headers.get("content-type") || "application/octet-stream",
  });

  assignFileInput(asset, file);
  setAssetStatus(asset, `server ${formatBytes(file.size)}`, "ok");
  appendLog(`BROWSER_ASSET_AUTO result=pass name=${asset.key} file=${JSON.stringify(filename)} size=${file.size}`);
  return true;
}

async function autoLoadServerAssets() {
  autoLoadingAssets = true;
  validateAssets();

  const loaded = new Set();
  for (const asset of assets) {
    if (asset.key === "dvd") {
      continue;
    }
    try {
      if (await loadServerAsset(asset)) {
        loaded.add(asset.key);
      }
    } catch (error) {
      appendLog(`BROWSER_ASSET_AUTO result=fail name=${asset.key} reason=${JSON.stringify(error.message)}`);
    }
  }

  if (loaded.has("flash") && loaded.has("hdd")) {
    refs.requireHddInput.checked = true;
    if ((Number(refs.timeoutInput.value) || 0) < 60000) {
      refs.timeoutInput.value = "60000";
    }
    saveConfig();
  }

  autoLoadingAssets = false;
  validateAssets();
}

const traceOptionSpecs = [
  {
    key: "xbeExecProbeLimit",
    globalKey: "xemuBrowserBootXbeExecProbeLimit",
    name: "xbe_exec_probe_limit",
  },
  {
    key: "xbeExecProbeStride",
    globalKey: "xemuBrowserBootXbeExecProbeStride",
    name: "xbe_exec_probe_stride",
  },
  {
    key: "xbePhysCompareLimit",
    globalKey: "xemuBrowserBootXbePhysCompareLimit",
    name: "xbe_phys_compare_limit",
  },
  {
    key: "xbeKernelLoopLimit",
    globalKey: "xemuBrowserBootXbeKernelLoopLimit",
    name: "xbe_kernel_loop_limit",
  },
  {
    key: "xbeKernelLoopAfterIdleLimit",
    globalKey: "xemuBrowserBootXbeKernelLoopAfterIdleLimit",
    name: "xbe_kernel_loop_after_idle_limit",
  },
  {
    key: "xbeKernelLoopMinHits",
    globalKey: "xemuBrowserBootXbeKernelLoopMinHits",
    name: "xbe_kernel_loop_min_hits",
  },
  {
    key: "xbeMemoryWatchPhys",
    globalKey: "xemuBrowserBootXbeMemoryWatchPhys",
    name: "xbe_memory_watch_phys",
  },
  {
    key: "xbeMemoryWatchLimit",
    globalKey: "xemuBrowserBootXbeMemoryWatchLimit",
    name: "xbe_memory_watch_limit",
  },
  {
    key: "xbeMemoryWatchAccess",
    globalKey: "xemuBrowserBootXbeMemoryWatchAccess",
    name: "xbe_memory_watch_access",
  },
  {
    key: "xbePicIrqLimit",
    globalKey: "xemuBrowserBootXbePicIrqLimit",
    name: "xbe_pic_irq_limit",
  },
  {
    key: "xbeCpuHardIrqLimit",
    globalKey: "xemuBrowserBootXbeCpuHardIrqLimit",
    name: "xbe_cpu_hard_irq_limit",
  },
  {
    key: "xbeIretLimit",
    globalKey: "xemuBrowserBootXbeIretLimit",
    name: "xbe_iret_limit",
  },
  {
    key: "xbePitIrqLimit",
    globalKey: "xemuBrowserBootXbePitIrqLimit",
    name: "xbe_pit_irq_limit",
  },
  {
    key: "xbeMainLoopTimerLimit",
    globalKey: "xemuBrowserBootXbeMainLoopTimerLimit",
    name: "xbe_main_loop_timer_limit",
  },
  {
    key: "browserHeadlessTimerPumpProgressLimit",
    globalKey: "xemuBrowserBootHeadlessTimerPumpProgressLimit",
    name: "browser_headless_timer_pump_progress_limit",
  },
  {
    key: "browserHeadlessTimerPumpMode",
    globalKey: "xemuBrowserBootHeadlessTimerPumpMode",
    name: "browser_headless_timer_pump_mode",
  },
  {
    key: "xbeTcgTimerPumpInterval",
    globalKey: "xemuBrowserBootXbeTcgTimerPumpInterval",
    name: "xbe_tcg_timer_pump_interval",
  },
  {
    key: "xbeTcgTimerPumpAfterIdleLimit",
    globalKey: "xemuBrowserBootXbeTcgTimerPumpAfterIdleLimit",
    name: "xbe_tcg_timer_pump_after_idle_limit",
  },
  {
    key: "xbeTcgTimerPumpMode",
    globalKey: "xemuBrowserBootXbeTcgTimerPumpMode",
    name: "xbe_tcg_timer_pump_mode",
  },
  {
    key: "xbeIdleBeforePfifoTransitionLimit",
    globalKey: "xemuBrowserBootXbeIdleBeforePfifoTransitionLimit",
    name: "xbe_idle_before_pfifo_transition_limit",
  },
  {
    key: "xbeIrqAfterPfifoEmptyOnly",
    globalKey: "xemuBrowserBootXbeIrqAfterPfifoEmptyOnly",
    name: "xbe_irq_after_pfifo_empty_only",
  },
  {
    key: "xbeIrqWatch",
    globalKey: "xemuBrowserBootXbeIrqWatch",
    name: "xbe_irq_watch",
  },
];

function browserTraceOptions() {
  const source = globalThis.xemuBrowserBootTraceOptions || {};
  const options = {};

  for (const spec of traceOptionSpecs) {
    const value = source[spec.key] ?? globalThis[spec.globalKey] ?? "";
    const text = String(value).trim();
    if (text) {
      options[spec.key] = text;
    }
  }

  return options;
}

async function runWithAssets(selectedAssets, runMode) {
  const { buildDir, timeoutMs } = currentConfig();
  const pcrtcVblankMode = String(globalThis.xemuBrowserBootPcrtcVblankMode || "").trim();
  const browserIcount = String(globalThis.xemuBrowserBootIcount || "").trim();
  const traceOptions = browserTraceOptions();
  const startedAt = Date.now();
  saveConfig();
  refs.buildLabel.textContent = `${buildDir}/qemu-system-i386.js`;
  refs.logOutput.textContent = "";
  transcript = [];
  logBrowserMetadata(buildDir, timeoutMs);
  appendLog(`BROWSER_RUN_MODE mode=${runMode}`);
  if (pcrtcVblankMode) {
    appendLog(`BROWSER_DIAGNOSTIC name=pcrtc_vblank_mode value=${pcrtcVblankMode}`);
  }
  if (browserIcount) {
    appendLog(`BROWSER_DIAGNOSTIC name=browser_icount value=${browserIcount}`);
  }
  for (const spec of traceOptionSpecs) {
    if (traceOptions[spec.key]) {
      appendLog(`BROWSER_DIAGNOSTIC name=${spec.name} value=${traceOptions[spec.key]}`);
    }
  }
  await logArtifactMetadata(buildDir);

  for (const selected of selectedAssets) {
    appendLog(`BROWSER_ASSET name=${selected.key} file=${selected.name} size=${selected.size}`);
  }

  worker = new Worker("./worker.js", { type: "module" });
  refs.startBtn.disabled = true;
  refs.syntheticBtn.disabled = true;
  refs.stopBtn.disabled = false;

  worker.onmessage = (event) => {
    const { type, line, result, base64, frame } = event.data || {};
    if (type === "log") {
      appendLog(line);
    } else if (type === "eeprom") {
      savePersistedEeprom(base64);
    } else if (type === "displayFrame") {
      drawBrowserDisplayFrame(frame).catch((error) => {
        appendLog(`BROWSER_DISPLAY_CAPTURE result=fail reason=${JSON.stringify(error.message)}`);
      });
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
    pcrtcVblankMode,
    browserIcount,
    traceOptions,
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
  asset.input.addEventListener("change", () => {
    asset.serverFile = null;
    validateAssets();
  });
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
  captureDisplayEvidence().catch((error) => {
    appendLog(`BROWSER_DISPLAY_CAPTURE result=fail reason=${JSON.stringify(error.message)}`);
  });
});

loadConfig();
renderCapabilities();
drawSyntheticFramebuffer();
globalThis.xemuBrowserDisplayCapture = captureDisplayEvidence;
validateAssets();
autoLoadServerAssets().catch((error) => {
  autoLoadingAssets = false;
  appendLog(`BROWSER_ASSET_AUTO result=fail reason=${JSON.stringify(error.message)}`);
  validateAssets();
});
