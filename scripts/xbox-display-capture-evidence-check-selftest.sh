#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-display-capture-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-display-capture-evidence.XXXXXX")"
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
        printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

run_case_with_env() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local log_path="${tmp_dir}/${name}.log"
    local out_path="${tmp_dir}/${name}.out"
    shift 3

    "$@" >"${log_path}"

    if XEMU_DISPLAY_EVIDENCE_ALLOW_SYNTHETIC=1 "${script}" "${log_path}" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_missing_b4() {
    cat <<'EOF'
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef source=browser-canvas
EOF
}

case_missing_capture() {
    cat <<'EOF'
BOOT_MARK b4 display=visible
EOF
}

case_empty_capture() {
    cat <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=no hash=0123456789abcdef source=browser-canvas
EOF
}

case_bad_hash() {
    cat <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=not-a-hash source=browser-canvas
EOF
}

case_bad_source() {
    cat <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef source=manual-note
EOF
}

case_synthetic_source() {
    cat <<'EOF'
BOOT_MARK b4 display=visible source=synthetic-framebuffer
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef source=synthetic-framebuffer
EOF
}

case_pass() {
    cat <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef source=browser-canvas
EOF
}

run_case missing-b4 1 'reason=missing-b4-marker' case_missing_b4
run_case missing-capture 1 'reason=missing-display-capture' case_missing_capture
run_case empty-capture 1 'reason=capture-empty' case_empty_capture
run_case bad-hash 1 'reason=bad-hash' case_bad_hash
run_case bad-source 1 'reason=bad-source' case_bad_source
run_case synthetic-source 1 'reason=synthetic-source-not-real' case_synthetic_source
run_case_with_env synthetic-source-allowed 0 'DISPLAY_CAPTURE_EVIDENCE result=pass' case_synthetic_source
run_case pass 0 'DISPLAY_CAPTURE_EVIDENCE result=pass' case_pass

printf 'DISPLAY_CAPTURE_EVIDENCE_SELFTEST_RESULT result=pass cases=8\n'
