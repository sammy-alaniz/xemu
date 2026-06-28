#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-synthetic-matrix.sh

Runs a non-proprietary synthetic native-vs-wasm boot matrix. This creates a
zero-filled flash image and verifies only the harness path through synthetic B2
markers. It does not prove real Xbox firmware or HDD boot behavior.

Optional controls:
  XEMU_SYNTHETIC_FIXTURE_DIR  Fixture dir. Default: /tmp/xemu-synthetic-fixtures.
  XEMU_SYNTHETIC_OUT_DIR      Output dir. Default: build-synthetic-boot-matrix.
  XEMU_SMOKE_MS               Per-smoke timeout ms. Default: 1000.
  XEMU_MATRIX_SKIP_NATIVE     Passed through to xbox-boot-smoke-matrix.sh.
  XEMU_MATRIX_SKIP_WASM       Passed through to xbox-boot-smoke-matrix.sh.
  XEMU_SYNTHETIC_SKIP_BROWSER_BLOCK
                              Skip browser-block callback smoke when set to 1.

Evidence files are written under XEMU_SYNTHETIC_OUT_DIR, including
synthetic-matrix.log, the nested matrix.log, and browser-block-callback-smoke.log.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fixture_dir="${XEMU_SYNTHETIC_FIXTURE_DIR:-/tmp/xemu-synthetic-fixtures}"
out_dir="${XEMU_SYNTHETIC_OUT_DIR:-${repo_root}/build-synthetic-boot-matrix}"
skip_browser_block="${XEMU_SYNTHETIC_SKIP_BROWSER_BLOCK:-0}"
case "${out_dir}" in
    /*) ;;
    *) out_dir="${repo_root}/${out_dir}" ;;
esac

flash_path="${fixture_dir}/flash.bin"

mkdir -p "${fixture_dir}" "${out_dir}"
synthetic_log="${out_dir}/synthetic-matrix.log"
rm -f "${synthetic_log}"
exec > >(tee "${synthetic_log}") 2>&1

dd if=/dev/zero of="${flash_path}" bs=1024 count=1024 status=none

XEMU_FLASH="${flash_path}" \
XEMU_MATRIX_EXPECT_LEVEL=B0 \
XEMU_MATRIX_COMPARE_LEVEL=B2 \
XEMU_MATRIX_OUT_DIR="${out_dir}" \
XEMU_SMOKE_MS="${XEMU_SMOKE_MS:-1000}" \
    "${repo_root}/scripts/xbox-boot-smoke-matrix.sh"

if [ "${skip_browser_block}" != "1" ]; then
    XEMU_BROWSER_BLOCK_OUT_DIR="${out_dir}/browser-block" \
    XEMU_BROWSER_BLOCK_MS="${XEMU_BROWSER_BLOCK_MS:-${XEMU_SMOKE_MS:-1000}}" \
        "${repo_root}/scripts/xbox-browser-block-callback-smoke.sh"
fi

printf 'BOOT_SYNTHETIC_MATRIX_RESULT result=pass out_dir=%s fixture_dir=%s\n' \
    "${out_dir}" "${fixture_dir}"
