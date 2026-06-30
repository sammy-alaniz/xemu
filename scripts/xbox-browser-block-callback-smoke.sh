#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-block-callback-smoke.sh

Runs the wasm build under Node with browser-block HDD storage configured at
/xemu-browser-block/xbox_hdd.img. By default it uses synthetic no-private-assets
fixtures. If XEMU_FLASH and XEMU_HDD are set, it mounts those private local
fixtures read-only and runs the same browser-block bridge against them.

Optional controls:
  XEMU_SMOKE_WASM_IMAGE      Wasm Docker image. Default: xemu-wasm-build:latest.
  XEMU_SMOKE_WASM_BUILD_DIR  Wasm build dir. Default: build-wasm-pic.
  XEMU_BROWSER_BLOCK_OUT_DIR Output dir. Default: build-browser-block-callback-smoke.
  XEMU_BROWSER_BLOCK_MS      Timeout ms. Default: 1000.
  XEMU_BROWSER_BLOCK_HDD_MB  Synthetic HDD size MiB. Default: 16.

Optional real fixtures:
  XEMU_FLASH                 Xbox flash/BIOS image.
  XEMU_HDD                   Xbox HDD image.
  XEMU_MCPX                  MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM                EEPROM image. Must be exactly 256 bytes.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
wasm_image="${XEMU_SMOKE_WASM_IMAGE:-xemu-wasm-build:latest}"
wasm_build_dir="${XEMU_SMOKE_WASM_BUILD_DIR:-build-wasm-pic}"
out_dir="${XEMU_BROWSER_BLOCK_OUT_DIR:-${repo_root}/build-browser-block-callback-smoke}"
timeout_ms="${XEMU_BROWSER_BLOCK_MS:-1000}"
hdd_mb="${XEMU_BROWSER_BLOCK_HDD_MB:-16}"
log_path="${out_dir}/browser-block-callback-smoke.log"
runner_path="${out_dir}/browser-block-callback-smoke.mjs"
fixture_mode="synthetic"

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

require_file() {
    local name="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        echo "${name} is required" >&2
        exit 2
    fi

    if [ ! -f "${path}" ]; then
        echo "${name} does not exist: ${path}" >&2
        exit 2
    fi
}

validate_exact_size() {
    local name="$1"
    local path="$2"
    local expected="$3"
    local actual

    actual="$(file_size "${path}")"
    if [ "${actual}" != "${expected}" ]; then
        echo "${name} must be ${expected} bytes, got ${actual}: ${path}" >&2
        exit 2
    fi
}

case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac

if [ ! -f "${repo_root}/${wasm_build_dir}/qemu-system-i386.js" ] ||
   [ ! -f "${repo_root}/${wasm_build_dir}/qemu-system-i386.wasm" ]; then
    echo "Wasm build artifacts are missing in ${repo_root}/${wasm_build_dir}" >&2
    echo "Run scripts/docker-build-xemu-wasm.sh first." >&2
    exit 2
fi

if [ -n "${XEMU_FLASH:-}" ] || [ -n "${XEMU_HDD:-}" ]; then
    require_file "XEMU_FLASH" "${XEMU_FLASH:-}"
    require_file "XEMU_HDD" "${XEMU_HDD:-}"
    fixture_mode="real"
fi

if [ -n "${XEMU_MCPX:-}" ]; then
    require_file "XEMU_MCPX" "${XEMU_MCPX}"
    validate_exact_size "XEMU_MCPX" "${XEMU_MCPX}" 512
fi

if [ -n "${XEMU_EEPROM:-}" ]; then
    require_file "XEMU_EEPROM" "${XEMU_EEPROM}"
    validate_exact_size "XEMU_EEPROM" "${XEMU_EEPROM}" 256
fi

mkdir -p "${out_dir}"
rm -f "${log_path}"

cat >"${runner_path}" <<'EOF'
import fs from "node:fs";

const buildDir = process.env.XEMU_SMOKE_WASM_BUILD_DIR || "build-wasm-pic";
const { default: Factory } = await import(`/workspace/${buildDir}/qemu-system-i386.js`);

const timeoutMs = Number(process.env.XEMU_NODE_TIMEOUT_MS) || 1000;
const hddBytes = (Number(process.env.XEMU_BROWSER_BLOCK_HDD_MB) || 16) * 1024 * 1024;
const fixtureMode = process.env.XEMU_BROWSER_BLOCK_FIXTURE_MODE || "synthetic";
const startedAt = Date.now();
const blocksByPath = new Map();
const blocksById = new Map();
let nextId = 1;

function syntheticBytes(size, seed) {
  const bytes = new Uint8Array(size);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = (seed + i * 17 + (i >>> 8) * 29) & 0xff;
  }
  return bytes;
}

const flash = fixtureMode === "real" ? fs.readFileSync("/xemu-real/flash.bin") : new Uint8Array(1024 * 1024);
const eeprom = fs.existsSync("/xemu-real/eeprom.bin") ? fs.readFileSync("/xemu-real/eeprom.bin") : new Uint8Array(256);
const mcpxPath = fs.existsSync("/xemu-real/mcpx.bin") ? "/xemu-fixtures/mcpx.bin" : "";
const hddPath = "/xemu-real/xbox_hdd.img";
const hdd = fixtureMode === "real" ? null : syntheticBytes(hddBytes, 0x58);
const hddFile = fixtureMode === "real" ? fs.openSync(hddPath, "r") : -1;
const hddSize = fixtureMode === "real" ? fs.statSync(hddPath).size : hdd.byteLength;
blocksByPath.set("/xemu-browser-block/xbox_hdd.img", {
  key: "hdd",
  backend: fixtureMode === "real" ? "node-file" : "node-synthetic",
  bytes: hdd,
  fd: hddFile,
  size: hddSize,
});

const config = `[general]
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
bootrom_path = "${mcpxPath}"
flashrom_path = "/xemu-fixtures/flash.bin"
eeprom_path = "/xemu-fixtures/eeprom.bin"
hdd_path = "/xemu-browser-block/xbox_hdd.img"
dvd_path = ""

[net]
enable = false
`;

setTimeout(() => {
  console.log(`BOOT_SMOKE_RESULT reason=timeout elapsed_ms=${Date.now() - startedAt} exit=0`);
  process.exit(0);
}, timeoutMs);

const moduleArg = {
  arguments: [
    "-config_path", "/xemu-smoke/xemu-smoke.toml",
    "-headless_boot_ms", String(timeoutMs),
  ],
  print: (line) => console.log(line),
  printErr: (line) => console.log(line),
};

moduleArg.xemuBrowserBlockOpen = (path, writable) => {
  const block = blocksByPath.get(path);
  if (!block) {
    console.log(`BROWSER_BLOCK_OPEN result=fail path=${JSON.stringify(path)}`);
    return -1;
  }
  const id = nextId++;
  blocksById.set(id, block);
  console.log(`BROWSER_BLOCK_OPEN result=pass id=${id} asset=${block.key} backend=${block.backend} writable=${writable ? "yes" : "no"} size=${block.size}`);
  return id;
};

moduleArg.xemuBrowserBlockGetSize = (id) => {
  const block = blocksById.get(id);
  return block ? block.size : -1;
};

moduleArg.xemuBrowserBlockRead = (id, offset, ptr, bytes) => {
  const block = blocksById.get(id);
  const heap = globalThis.xemuBrowserBlockHeap || moduleArg.HEAPU8;
  offset = Number(offset);
  if (!block || offset < 0 || bytes < 0 || offset + bytes > block.size) {
    console.log(`BROWSER_BLOCK_READ result=fail id=${id} offset=${offset} bytes=${bytes}`);
    return -1;
  }
  if (block.fd >= 0) {
    const target = heap.subarray(ptr, ptr + bytes);
    const actual = fs.readSync(block.fd, target, 0, bytes, offset);
    if (actual !== bytes) {
      console.log(`BROWSER_BLOCK_READ result=fail id=${id} offset=${offset} bytes=${bytes} actual=${actual}`);
      return -1;
    }
  } else {
    heap.set(block.bytes.subarray(offset, offset + bytes), ptr);
  }
  console.log(`BROWSER_BLOCK_READ result=pass id=${id} asset=${block.key} backend=${block.backend} offset=${offset} bytes=${bytes}`);
  console.log(`BOOT_MARK b3 browser_block=read id=${id} offset=${offset} bytes=${bytes}`);
  return 0;
};

moduleArg.xemuBrowserBlockWrite = (id, offset, ptr, bytes) => {
  const block = blocksById.get(id);
  const heap = globalThis.xemuBrowserBlockHeap || moduleArg.HEAPU8;
  offset = Number(offset);
  if (!block || offset < 0 || bytes < 0 || offset + bytes > block.size) {
    console.log(`BROWSER_BLOCK_WRITE result=fail id=${id} offset=${offset} bytes=${bytes}`);
    return -1;
  }
  if (block.fd >= 0) {
    console.log(`BROWSER_BLOCK_WRITE result=fail id=${id} reason=read-only-file offset=${offset} bytes=${bytes}`);
    return -1;
  }
  block.bytes.set(heap.subarray(ptr, ptr + bytes), offset);
  console.log(`BROWSER_BLOCK_WRITE result=pass id=${id} asset=${block.key} backend=${block.backend} offset=${offset} bytes=${bytes}`);
  return 0;
};

moduleArg.xemuBrowserBlockFlush = (id) => {
  console.log(`BROWSER_BLOCK_FLUSH result=${blocksById.has(id) ? "pass" : "fail"} id=${id}`);
  return blocksById.has(id) ? 0 : -1;
};

moduleArg.xemuBrowserBlockClose = (id) => {
  const block = blocksById.get(id);
  if (block && block.fd >= 0) {
    fs.closeSync(block.fd);
    block.fd = -1;
  }
  const had = blocksById.delete(id);
  console.log(`BROWSER_BLOCK_CLOSE result=${had ? "pass" : "skip"} id=${id}`);
};

globalThis.xemuBrowserBlockOpen = moduleArg.xemuBrowserBlockOpen;
globalThis.xemuBrowserBlockGetSize = moduleArg.xemuBrowserBlockGetSize;
globalThis.xemuBrowserBlockRead = moduleArg.xemuBrowserBlockRead;
globalThis.xemuBrowserBlockWrite = moduleArg.xemuBrowserBlockWrite;
globalThis.xemuBrowserBlockFlush = moduleArg.xemuBrowserBlockFlush;
globalThis.xemuBrowserBlockClose = moduleArg.xemuBrowserBlockClose;

moduleArg.preRun = [() => {
  moduleArg.FS.mkdir("/xemu-fixtures");
  moduleArg.FS.writeFile("/xemu-fixtures/boot_trace_context.txt", "browser-block-callback\n");
  moduleArg.FS.writeFile("/xemu-fixtures/flash.bin", flash);
  moduleArg.FS.writeFile("/xemu-fixtures/eeprom.bin", eeprom);
  if (mcpxPath) {
    moduleArg.FS.writeFile("/xemu-fixtures/mcpx.bin", fs.readFileSync("/xemu-real/mcpx.bin"));
  }
  moduleArg.FS.mkdir("/xemu-smoke");
  moduleArg.FS.writeFile("/xemu-smoke/xemu-smoke.toml", config);
  moduleArg.FS.mkdirTree("/home/web_user/.local/share/xemu/xemu");
}];

await Factory(moduleArg);
EOF

docker_args=(
    docker run --rm -t
    --user "$(id -u):$(id -g)"
    -e HOME=/tmp/xemu-home
    -e XEMU_HEADLESS_BOOT=1
    -e XEMU_BOOT_TRACE=1
    -e XEMU_BOOT_TRACE_CONTEXT=browser-block-callback
    -e XEMU_HEADLESS_BOOT_MS="${timeout_ms}"
    -e XEMU_NODE_TIMEOUT_MS="${timeout_ms}"
    -e XEMU_BROWSER_BLOCK_HDD_MB="${hdd_mb}"
    -e XEMU_BROWSER_BLOCK_FIXTURE_MODE="${fixture_mode}"
    -e XEMU_SMOKE_WASM_BUILD_DIR="${wasm_build_dir}"
    -v "${repo_root}:/workspace"
    -v "${out_dir}:/xemu-smoke-out"
)

if [ "${fixture_mode}" = "real" ]; then
    docker_args+=(
        -v "${XEMU_FLASH}:/xemu-real/flash.bin:ro"
        -v "${XEMU_HDD}:/xemu-real/xbox_hdd.img:ro"
    )
    if [ -n "${XEMU_MCPX:-}" ]; then
        docker_args+=(-v "${XEMU_MCPX}:/xemu-real/mcpx.bin:ro")
    fi
    if [ -n "${XEMU_EEPROM:-}" ]; then
        docker_args+=(-v "${XEMU_EEPROM}:/xemu-real/eeprom.bin:ro")
    fi
fi

docker_args+=(
    -w "/workspace/${wasm_build_dir}"
    "${wasm_image}"
    timeout "$(( (timeout_ms + 999) / 1000 + 2 ))s"
    node "/xemu-smoke-out/$(basename "${runner_path}")"
)

set +e
"${docker_args[@]}" >"${log_path}" 2>&1
run_status=$?
set -e

if [ "${run_status}" -ne 0 ] && [ "${run_status}" -ne 124 ]; then
    printf 'BROWSER_BLOCK_CALLBACK_SMOKE result=fail reason=node-run-failed exit=%s log=%s\n' \
        "${run_status}" "${log_path}" >&2
    sed -n '1,120p' "${log_path}" >&2 || true
    exit 1
fi

if ! grep -q '^BOOT_SMOKE_RESULT ' "${log_path}"; then
    printf 'BOOT_SMOKE_RESULT reason=host-timeout elapsed_ms=%s exit=124\n' "${timeout_ms}" >>"${log_path}"
fi

open_seen="no"
read_seen="no"

if grep -q 'BOOT_MARK b3 browser_block=open ' "${log_path}" &&
   grep -q '^BROWSER_BLOCK_OPEN result=pass ' "${log_path}"; then
    open_seen="yes"
fi

if grep -q 'BOOT_MARK b3 browser_block=read ' "${log_path}" &&
   grep -q '^BROWSER_BLOCK_READ result=pass ' "${log_path}"; then
    read_seen="yes"
fi

if [ "${open_seen}" != "yes" ]; then
    printf 'BROWSER_BLOCK_CALLBACK_SMOKE result=fail reason=missing-browser-block-open log=%s\n' "${log_path}" >&2
    grep -E '(BOOT_MARK b3 browser_block=|^BROWSER_BLOCK_|^BOOT_SMOKE_RESULT )' "${log_path}" >&2 || true
    exit 1
fi

if [ "${fixture_mode}" = "real" ] && [ "${read_seen}" != "yes" ]; then
    printf 'BROWSER_BLOCK_CALLBACK_SMOKE result=fail mode=real reason=missing-browser-block-read log=%s\n' "${log_path}" >&2
    grep -E '(BOOT_MARK b3 browser_block=|^BROWSER_BLOCK_|^BOOT_SMOKE_RESULT )' "${log_path}" >&2 || true
    exit 1
fi

if [ "${fixture_mode}" = "real" ]; then
    hdd_size="$(file_size "${XEMU_HDD}")"
else
    hdd_size="$(( hdd_mb * 1024 * 1024 ))"
fi

printf 'BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=%s open=%s read=%s hdd_bytes=%s log=%s\n' \
    "${fixture_mode}" "${open_seen}" "${read_seen}" "${hdd_size}" "${log_path}"
grep -E '(BOOT_MARK b3 browser_block=|^BROWSER_BLOCK_|^BOOT_SMOKE_RESULT )' "${log_path}" || true
