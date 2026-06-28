#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-b3-evidence-check.sh <log-file>

Validates the real B3 evidence contract. The log must show:

  BOOT_REAL_B3_PREFLIGHT_RESULT result=pass
  BOOT_MATRIX_RESULT result=pass ... expected=B3 ...
  BOOT_MARK_COMPARE result=pass ... expected=B3 ...
  BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real open=yes read=yes ...
  BROWSER_BLOCK_READ result=pass ... asset=hdd backend=node-file ...
  BOOT_MARK b3 browser_block=read ...
  a passing real browser runtime evidence line
  BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass ...

This script checks evidence already captured by the real B3 matrix. It does not
start emulation or inspect private fixture contents.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

log_path="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

if [ -z "${log_path}" ]; then
    printf 'REAL_B3_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'REAL_B3_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
    exit 2
fi

require_pattern() {
    local reason="$1"
    local pattern="$2"

    if ! grep -Eq "${pattern}" "${log_path}"; then
        printf 'REAL_B3_EVIDENCE result=fail reason=%s log=%s\n' "${reason}" "${log_path}" >&2
        exit 1
    fi
}

require_pattern missing-preflight-pass '^BOOT_REAL_B3_PREFLIGHT_RESULT result=pass '
require_pattern missing-b3-matrix-pass '^BOOT_MATRIX_RESULT result=pass .*expected=B3'
require_pattern missing-b3-marker-compare '^BOOT_MARK_COMPARE result=pass .*expected=B3'
require_pattern missing-browser-block-real-pass '^BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real .*open=yes .*read=yes'
require_pattern missing-browser-block-node-file-read '^BROWSER_BLOCK_READ result=pass .*asset=hdd .*backend=node-file '
require_pattern missing-browser-block-read '^BOOT_MARK b3 browser_block=read '
require_pattern missing-real-b3-result '^BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass '

if ! "${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh" "${log_path}" >/dev/null 2>&1; then
    printf 'REAL_B3_EVIDENCE result=fail reason=browser-runtime-evidence log=%s\n' "${log_path}" >&2
    exit 1
fi

printf 'REAL_B3_EVIDENCE result=pass log=%s\n' "${log_path}"
