#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-host-check.sh [base-url]

Checks the browser boot host shell and wasm artifacts through HTTP. The server
must already be running, for example:

  scripts/serve-xbox-browser-boot.py --port 8765

Default base-url: http://127.0.0.1:8765
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

base_url="${1:-http://127.0.0.1:8765}"
base_url="${base_url%/}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fetch_headers() {
    local name="$1"
    local url="$2"
    local out="${tmp_dir}/${name}.headers"

    curl -fsSI "${url}" >"${out}"
    printf '%s\n' "${out}"
}

require_header() {
    local file="$1"
    local header="$2"
    local expected="$3"

    if ! awk -v header="${header}" -v expected="${expected}" '
        BEGIN { found = 0 }
        {
            line = $0
            sub(/\r$/, "", line)
            split(line, parts, ":")
            key = tolower(parts[1])
            if (key == tolower(header)) {
                value = substr(line, length(parts[1]) + 2)
                sub(/^ +/, "", value)
                if (tolower(value) == tolower(expected)) {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${file}"; then
        printf 'BROWSER_HOST_CHECK result=fail reason=missing-header header=%s expected=%s file=%s\n' \
            "${header}" "${expected}" "${file}" >&2
        cat "${file}" >&2
        exit 1
    fi
}

require_status_ok() {
    local file="$1"

    if ! head -n 1 "${file}" | grep -Eq ' 200 '; then
        printf 'BROWSER_HOST_CHECK result=fail reason=http-status file=%s\n' "${file}" >&2
        cat "${file}" >&2
        exit 1
    fi
}

require_content_type() {
    local file="$1"
    local pattern="$2"

    if ! grep -Eiq "^content-type: ${pattern}" "${file}"; then
        printf 'BROWSER_HOST_CHECK result=fail reason=content-type pattern=%s file=%s\n' \
            "${pattern}" "${file}" >&2
        cat "${file}" >&2
        exit 1
    fi
}

index_headers="$(fetch_headers index "${base_url}/browser/xbox-boot/")"
style_headers="$(fetch_headers style "${base_url}/browser/xbox-boot/style.css")"
main_headers="$(fetch_headers main "${base_url}/browser/xbox-boot/main.js")"
worker_headers="$(fetch_headers worker "${base_url}/browser/xbox-boot/worker.js")"
block_headers="$(fetch_headers block "${base_url}/browser/xbox-boot/block-storage.mjs")"
js_headers="$(fetch_headers js "${base_url}/build-wasm-pic/qemu-system-i386.js")"
wasm_headers="$(fetch_headers wasm "${base_url}/build-wasm-pic/qemu-system-i386.wasm")"
index_body="${tmp_dir}/index.html"
main_body="${tmp_dir}/main.js"
worker_body="${tmp_dir}/worker.js"
block_body="${tmp_dir}/block-storage.mjs"
curl -fsS "${base_url}/browser/xbox-boot/" >"${index_body}"
curl -fsS "${base_url}/browser/xbox-boot/main.js" >"${main_body}"
curl -fsS "${base_url}/browser/xbox-boot/worker.js" >"${worker_body}"
curl -fsS "${base_url}/browser/xbox-boot/block-storage.mjs" >"${block_body}"

for file in \
    "${index_headers}" \
    "${style_headers}" \
    "${main_headers}" \
    "${worker_headers}" \
    "${block_headers}" \
    "${js_headers}" \
    "${wasm_headers}"
do
    require_status_ok "${file}"
    require_header "${file}" "Cross-Origin-Opener-Policy" "same-origin"
    require_header "${file}" "Cross-Origin-Embedder-Policy" "require-corp"
    require_header "${file}" "Cross-Origin-Resource-Policy" "same-origin"
done

require_content_type "${index_headers}" 'text/html'
require_content_type "${style_headers}" 'text/css'
require_content_type "${main_headers}" 'text/javascript|application/javascript'
require_content_type "${worker_headers}" 'text/javascript|application/javascript'
require_content_type "${block_headers}" 'text/javascript|application/javascript'
require_content_type "${js_headers}" 'text/javascript|application/javascript'
require_content_type "${wasm_headers}" 'application/wasm'

if ! grep -q 'id="syntheticBtn"' "${index_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-synthetic-button\n' >&2
    exit 1
fi

if ! grep -q 'id="displayCanvas"' "${index_body}" ||
   ! grep -q 'xemuBrowserDisplayCapture' "${main_body}" ||
   ! grep -q 'BROWSER_DISPLAY_CAPTURE' "${main_body}" ||
   ! grep -q 'synthetic-framebuffer' "${main_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-display-capture\n' >&2
    exit 1
fi

if ! grep -q 'BROWSER_RUN_MODE mode=' "${main_body}" ||
   ! grep -q 'BROWSER_ARTIFACT' "${main_body}" ||
   ! grep -q 'browser-main-timeout' "${main_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-transcript-metadata\n' >&2
    exit 1
fi

for capability in crossOriginIsolated SharedArrayBuffer Worker BigInt WebAssembly; do
    if ! grep -q "${capability}" "${main_body}"; then
        printf 'BROWSER_HOST_CHECK result=fail reason=missing-capability capability=%s\n' \
            "${capability}" >&2
        exit 1
    fi
done

if ! grep -q 'BROWSER_CAPABILITY name=' "${main_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-capability-transcript\n' >&2
    exit 1
fi

if ! grep -q 'xemu.browserBoot.config.v1' "${main_body}" ||
   ! grep -q 'BROWSER_CONFIG persisted=yes' "${main_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-config-persistence\n' >&2
    exit 1
fi

if ! grep -q 'xemu.browserBoot.eeprom.v1' "${main_body}" ||
   ! grep -q 'BROWSER_EEPROM_PERSIST' "${main_body}" ||
   ! grep -q 'BROWSER_EEPROM_EXPORT' "${worker_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-eeprom-persistence\n' >&2
    exit 1
fi

if ! grep -q 'class BlobBlockDevice' "${block_body}" ||
   ! grep -q 'class SyncMemoryBlockDevice' "${block_body}" ||
   ! grep -q 'class OverlayBlockDevice' "${block_body}" ||
   ! grep -q 'readSectors' "${block_body}" ||
   ! grep -q 'BROWSER_BLOCK_PROBE' "${worker_body}" ||
   ! grep -q 'BROWSER_BLOCK_MATERIALIZE' "${worker_body}" ||
   ! grep -q 'BROWSER_BLOCK_BACKING' "${worker_body}" ||
   ! grep -q 'BROWSER_BLOCK_SNAPSHOT' "${worker_body}" ||
   ! grep -q 'BROWSER_BLOCK_SNAPSHOT_PERSIST' "${worker_body}" ||
   ! grep -q 'BROWSER_BLOCK_SNAPSHOT_LOAD' "${worker_body}" ||
   ! grep -q 'SyncMemoryBlockDevice' "${worker_body}" ||
   ! grep -q 'chunksFromOverlaySnapshot' "${worker_body}" ||
   ! grep -q 'indexedDB.open' "${worker_body}" ||
   ! grep -q 'createSyncAccessHandle' "${worker_body}" ||
   ! grep -q 'backend=opfs-sync' "${worker_body}" ||
   ! grep -q 'xemuBrowserBlockRead' "${worker_body}" ||
   ! grep -q '/xemu-browser-block/xbox_hdd.img' "${worker_body}"; then
    printf 'BROWSER_HOST_CHECK result=fail reason=missing-block-storage-helper\n' >&2
    exit 1
fi

index_bytes="$(awk 'tolower($1) == "content-length:" { gsub(/\r/, "", $2); print $2 }' "${index_headers}" | tail -n 1)"
js_bytes="$(awk 'tolower($1) == "content-length:" { gsub(/\r/, "", $2); print $2 }' "${js_headers}" | tail -n 1)"
wasm_bytes="$(awk 'tolower($1) == "content-length:" { gsub(/\r/, "", $2); print $2 }' "${wasm_headers}" | tail -n 1)"

printf 'BROWSER_HOST_CHECK result=pass base_url=%s index_bytes=%s js_bytes=%s wasm_bytes=%s isolation_headers=all synthetic=yes transcript_metadata=yes capabilities=yes config_persistence=yes eeprom_persistence=yes block_storage=yes opfs_sync=yes block_snapshot=yes display_capture=yes\n' \
    "${base_url}" "${index_bytes:-unknown}" "${js_bytes:-unknown}" "${wasm_bytes:-unknown}"
