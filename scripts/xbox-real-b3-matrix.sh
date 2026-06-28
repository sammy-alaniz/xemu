#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-b3-matrix.sh

Runs the real-asset B3 evidence matrix. This requires private local Xbox assets
and does not copy or inspect their contents beyond size/path preflight.

Required:
  XEMU_FLASH       Path to Xbox flash/BIOS image.
  XEMU_HDD         Path to Xbox HDD image.

Optional:
  XEMU_MCPX        Path to MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM      Path to EEPROM image. Must be exactly 256 bytes.
  XEMU_DVD         Optional DVD image.

Controls:
  XEMU_REAL_B3_OUT_DIR             Output dir. Default: build-real-b3-matrix.
  XEMU_REAL_B3_FIXTURE_DIR         Optional fixture dir for auto-discovery.
  XEMU_REAL_B3_PREFLIGHT_ONLY      Validate fixtures only when set to 1.
  XEMU_REAL_B3_SKIP_NATIVE_WASM    Skip native/wasm matrix when set to 1.
  XEMU_REAL_B3_SKIP_BROWSER_BLOCK  Skip browser-block smoke when set to 1.
  XEMU_REAL_B3_SKIP_BROWSER_RUNTIME
                                  Skip real browser selected-assets smoke when set to 1.
  XEMU_SMOKE_MS                    Native/wasm timeout ms. Default: 10000.
  XEMU_BROWSER_BLOCK_MS            Browser-block timeout ms. Default: XEMU_SMOKE_MS.
  XEMU_REAL_B3_BROWSER_RUNTIME_PORT
                                  Port for browser runtime smoke. Default: 8788.
  XEMU_REAL_B3_BROWSER_RUNTIME_MS  Browser runtime timeout ms. Default: XEMU_SMOKE_MS.

Evidence files:
  real-fixture-manifest.log
  real-fixture-manifest/real-fixture-manifest.md
  real-fixture-ready.log
  fixtures.log
  native/boot-smoke.log
  wasm/boot-smoke.log
  compare.log
  browser-block/browser-block-callback-smoke.log
  browser-runtime.log
  real-b3-matrix.log
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
out_dir="${XEMU_REAL_B3_OUT_DIR:-${repo_root}/build-real-b3-matrix}"
fixture_dir="${XEMU_REAL_B3_FIXTURE_DIR:-}"
preflight_only="${XEMU_REAL_B3_PREFLIGHT_ONLY:-0}"
skip_native_wasm="${XEMU_REAL_B3_SKIP_NATIVE_WASM:-0}"
skip_browser_block="${XEMU_REAL_B3_SKIP_BROWSER_BLOCK:-0}"
skip_browser_runtime="${XEMU_REAL_B3_SKIP_BROWSER_RUNTIME:-0}"
smoke_ms="${XEMU_SMOKE_MS:-10000}"
browser_block_ms="${XEMU_BROWSER_BLOCK_MS:-${smoke_ms}}"
browser_runtime_port="${XEMU_REAL_B3_BROWSER_RUNTIME_PORT:-8788}"
browser_runtime_ms="${XEMU_REAL_B3_BROWSER_RUNTIME_MS:-${smoke_ms}}"

case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac

autodetect_fixture() {
    local env_name="$1"
    local file_name="$2"
    local candidate_dir
    local candidate_path

    if [ -n "${!env_name:-}" ]; then
        return
    fi

    for candidate_dir in \
        "${fixture_dir}" \
        "${repo_root}/fixtures" \
        "${repo_root}/xemu-fixtures"
    do
        if [ -z "${candidate_dir}" ]; then
            continue
        fi
        candidate_path="${candidate_dir}/${file_name}"
        if [ -f "${candidate_path}" ]; then
            export "${env_name}=${candidate_path}"
            printf 'BOOT_REAL_B3_AUTODETECT name=%s path=%s\n' "${env_name}" "${candidate_path}" >&2
            return
        fi
    done
}

require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "${name} is required" >&2
        exit 2
    fi
}

mkdir -p "${out_dir}"
matrix_log="${out_dir}/real-b3-matrix.log"
rm -f "${matrix_log}"

run_matrix() {
    autodetect_fixture XEMU_FLASH flash.bin
    autodetect_fixture XEMU_HDD xbox_hdd.img
    autodetect_fixture XEMU_MCPX mcpx.bin
    autodetect_fixture XEMU_EEPROM eeprom.bin
    autodetect_fixture XEMU_DVD dvd.iso

    "${repo_root}/scripts/xbox-real-fixture-manifest.sh" \
        "${out_dir}/real-fixture-manifest" | tee "${out_dir}/real-fixture-manifest.log"

    if ! XEMU_REAL_FIXTURE_READY_REQUIRE=1 \
        "${repo_root}/scripts/xbox-real-fixtures-ready.sh" | tee "${out_dir}/real-fixture-ready.log"; then
        printf 'BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures log=%s\n' \
            "${out_dir}/real-fixture-ready.log" >&2
        return 2
    fi

    require_env XEMU_FLASH
    require_env XEMU_HDD

    "${repo_root}/scripts/xbox-boot-fixtures-check.sh" | tee "${out_dir}/fixtures.log"
    printf 'BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=%s\n' "${out_dir}"

    if [ "${preflight_only}" = "1" ]; then
        return
    fi

    if [ "${skip_native_wasm}" != "1" ]; then
        XEMU_MATRIX_EXPECT_LEVEL=B3 \
        XEMU_MATRIX_COMPARE_LEVEL=B3 \
        XEMU_MATRIX_OUT_DIR="${out_dir}" \
        XEMU_SMOKE_MS="${smoke_ms}" \
            "${repo_root}/scripts/xbox-boot-smoke-matrix.sh"
    fi

    if [ "${skip_browser_block}" != "1" ]; then
        XEMU_BROWSER_BLOCK_OUT_DIR="${out_dir}/browser-block" \
        XEMU_BROWSER_BLOCK_MS="${browser_block_ms}" \
            "${repo_root}/scripts/xbox-browser-block-callback-smoke.sh"
    fi

    if [ "${skip_browser_runtime}" != "1" ]; then
        browser_runtime_log="${out_dir}/browser-runtime.log"
        if ! XEMU_BROWSER_RUNTIME_MODE=real \
            XEMU_BROWSER_RUNTIME_EXPECT_B3=1 \
            XEMU_BROWSER_RUNTIME_FIXTURE_DIR="${fixture_dir}" \
            XEMU_BROWSER_RUNTIME_PORT="${browser_runtime_port}" \
            XEMU_BROWSER_RUNTIME_BOOT_MS="${browser_runtime_ms}" \
            XEMU_BROWSER_RUNTIME_TIMEOUT_MS="$(( browser_runtime_ms + 60000 ))" \
                "${repo_root}/scripts/xbox-browser-runtime-smoke.sh" >"${browser_runtime_log}" 2>&1; then
            printf 'BOOT_REAL_B3_MATRIX_RESULT result=fail reason=browser-runtime log=%s\n' \
                "${browser_runtime_log}" >&2
            cat "${browser_runtime_log}" >&2
            return 1
        fi
        cat "${browser_runtime_log}"
    fi

    if [ "${skip_native_wasm}" = "1" ]; then
        native_wasm="skipped"
    else
        native_wasm="pass"
    fi

    if [ "${skip_browser_block}" = "1" ]; then
        browser_block="skipped"
    else
        browser_block="pass"
    fi

    if [ "${skip_browser_runtime}" = "1" ]; then
        browser_runtime="skipped"
    else
        browser_runtime="pass"
    fi

    printf 'BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=%s browser_block=%s browser_runtime=%s out_dir=%s\n' \
        "${native_wasm}" "${browser_block}" "${browser_runtime}" "${out_dir}"
}

set +e
run_matrix 2>&1 | tee "${matrix_log}"
matrix_status="${PIPESTATUS[0]}"
set -e

if [ "${matrix_status}" -ne 0 ]; then
    exit "${matrix_status}"
fi

if [ "${preflight_only}" != "1" ]; then
    set +e
    "${repo_root}/scripts/xbox-real-b3-evidence-check.sh" "${matrix_log}" 2>&1 | tee -a "${matrix_log}"
    evidence_status="${PIPESTATUS[0]}"
    set -e

    if [ "${evidence_status}" -ne 0 ]; then
        exit "${evidence_status}"
    fi
fi
