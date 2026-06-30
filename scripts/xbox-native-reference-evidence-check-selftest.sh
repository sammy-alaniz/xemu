#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-native-reference-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-native-reference-evidence.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local log_path="${tmp_dir}/${name}.log"
    local out_path="${tmp_dir}/${name}.out"
    local status
    shift 3

    "$@" >"${log_path}"

    if "${script}" "${log_path}" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'NATIVE_REFERENCE_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'NATIVE_REFERENCE_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'NATIVE_REFERENCE_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' \
        "${name}" "${status}"
}

valid_reference() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed frame=1 build_id=synthetic'
}

case_missing_reference() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=native-headless guest_pc=0x00010100'
}

case_reference_not_pass() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=fail context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
}

case_bad_context() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=browser-runtime source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
}

case_bad_source() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=browser-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
}

case_bad_hash() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=not-a-hash width=640 height=480 dashboard=xbe-executed'
}

case_bad_width() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=0 height=480 dashboard=xbe-executed'
}

case_bad_height() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=0 dashboard=xbe-executed'
}

case_bad_dashboard() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-loaded'
}

case_pass() {
    valid_reference
}

run_case missing-reference 1 'reason=missing-native-reference' case_missing_reference
run_case reference-not-pass 1 'reason=reference-not-pass' case_reference_not_pass
run_case bad-context 1 'reason=bad-context' case_bad_context
run_case bad-source 1 'reason=bad-source' case_bad_source
run_case bad-hash 1 'reason=bad-hash' case_bad_hash
run_case bad-width 1 'reason=bad-width' case_bad_width
run_case bad-height 1 'reason=bad-height' case_bad_height
run_case bad-dashboard 1 'reason=bad-dashboard' case_bad_dashboard
run_case pass 0 'NATIVE_REFERENCE_EVIDENCE result=pass' case_pass

printf 'NATIVE_REFERENCE_EVIDENCE_SELFTEST_RESULT result=pass cases=9\n'
