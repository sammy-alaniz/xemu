#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-real-b3-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-real-b3-evidence.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

base_log() {
    cat <<'EOF'
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=/tmp/real
BOOT_MARK_COMPARE result=pass mode=set baseline=B3 candidate=B3 expected=B3
BOOT_MATRIX_RESULT result=pass expected=B3 compare=B3 out_dir=/tmp/real
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real open=yes read=yes hdd_bytes=1024 log=/tmp/real/browser-block.log
BROWSER_BLOCK_READ result=pass id=1 asset=hdd backend=node-file offset=0 bytes=512
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real lines=42 run_mode=selected-assets hdd_asset=yes b3_marker=browser-block capability_sab=yes artifact_js=yes artifact_wasm=yes asset_validate=yes config_persist=yes
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required boot_result=timeout
BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass out_dir=/tmp/real
EOF
}

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local log_path="${tmp_dir}/${name}.log"
    local out_path="${tmp_dir}/${name}.out"
    shift 3

    "$@" >"${log_path}"

    if "${script}" "${log_path}" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'REAL_B3_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'REAL_B3_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'REAL_B3_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_missing_preflight() {
    base_log | grep -v '^BOOT_REAL_B3_PREFLIGHT_RESULT '
}

case_missing_compare() {
    base_log | grep -v '^BOOT_MARK_COMPARE '
}

case_missing_block_read() {
    base_log | grep -v '^BOOT_MARK b3 browser_block=read '
}

case_synthetic_block_backend() {
    base_log | sed '/^BROWSER_BLOCK_READ /s/backend=node-file/backend=node-synthetic/'
}

case_synthetic_runtime() {
    base_log | sed '/^BROWSER_RUNTIME_SMOKE /s/mode=real/mode=synthetic/'
}

case_skipped_runtime() {
    base_log | sed 's/browser_runtime=pass/browser_runtime=skipped/'
}

case_pass() {
    base_log
}

run_case missing-preflight 1 'reason=missing-preflight-pass' case_missing_preflight
run_case missing-compare 1 'reason=missing-b3-marker-compare' case_missing_compare
run_case missing-block-read 1 'reason=missing-browser-block-read' case_missing_block_read
run_case synthetic-block-backend 1 'reason=missing-browser-block-node-file-read' case_synthetic_block_backend
run_case synthetic-runtime 1 'reason=browser-runtime-evidence' case_synthetic_runtime
run_case skipped-runtime 1 'reason=missing-real-b3-result' case_skipped_runtime
run_case pass 0 'REAL_B3_EVIDENCE result=pass' case_pass

printf 'REAL_B3_EVIDENCE_SELFTEST_RESULT result=pass cases=7\n'
