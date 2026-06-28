#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-browser-runtime-evidence.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

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
        printf 'BROWSER_RUNTIME_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'BROWSER_RUNTIME_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'BROWSER_RUNTIME_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_missing() {
    cat <<'EOF'
BOOT_MARK b3 browser_block=read
EOF
}

case_synthetic() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=synthetic artifacts=yes asset_validate=yes b3=not-required boot_result=timeout
EOF
}

case_missing_capabilities() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" mode=real artifacts=yes asset_validate=yes b3=required boot_result=timeout
EOF
}

case_missing_config_persist() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes b3=required boot_result=timeout
EOF
}

case_b3_not_required() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=not-required boot_result=timeout
EOF
}

case_missing_boot_result() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required
EOF
}

case_missing_transcript() {
    cat <<'EOF'
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required boot_result=timeout
EOF
}

case_pass() {
    cat <<'EOF'
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real lines=42 run_mode=selected-assets hdd_asset=yes b3_marker=browser-block capability_sab=yes artifact_js=yes artifact_wasm=yes asset_validate=yes config_persist=yes
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required boot_result=timeout
EOF
}

run_case missing 1 'reason=missing-runtime-smoke' case_missing
run_case synthetic 1 'field=mode expected=real actual=synthetic' case_synthetic
run_case missing-capabilities 1 'field=capabilities expected=yes actual=missing' case_missing_capabilities
run_case missing-config-persist 1 'field=config_persist expected=yes actual=missing' case_missing_config_persist
run_case b3-not-required 1 'field=b3 expected=required actual=not-required' case_b3_not_required
run_case missing-boot-result 1 'reason=missing-boot-result' case_missing_boot_result
run_case missing-transcript 1 'reason=missing-runtime-transcript' case_missing_transcript
run_case pass 0 'BROWSER_RUNTIME_EVIDENCE result=pass' case_pass

printf 'BROWSER_RUNTIME_EVIDENCE_SELFTEST_RESULT result=pass cases=8\n'
