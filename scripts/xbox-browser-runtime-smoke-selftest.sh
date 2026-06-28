#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-browser-runtime-smoke-selftest.sh

Runs no-private-assets tests for xbox-browser-runtime-smoke.sh paths that exit
before launching the browser server. This verifies real-mode argument and
fixture preflight failures stay structured and actionable.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-browser-runtime-smoke.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-browser-runtime-smoke-selftest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_file() {
    local path="$1"
    local size="$2"

    dd if=/dev/zero of="${path}" bs=1 count=0 seek="${size}" status=none
}

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local out_path="${tmp_dir}/${name}.out"
    shift 3

    if "$@" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'BROWSER_RUNTIME_SMOKE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'BROWSER_RUNTIME_SMOKE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    printf 'BROWSER_RUNTIME_SMOKE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_bad_mode() {
    env -i PATH="${PATH}" \
        XEMU_BROWSER_RUNTIME_MODE=bad-mode \
            "${script}"
}

case_missing_real_flash() {
    env -i PATH="${PATH}" \
        XEMU_BROWSER_RUNTIME_MODE=real \
            "${script}"
}

case_missing_real_file() {
    env -i PATH="${PATH}" \
        XEMU_BROWSER_RUNTIME_MODE=real \
        XEMU_FLASH="${tmp_dir}/missing-flash.bin" \
        XEMU_HDD="${tmp_dir}/missing-hdd.img" \
            "${script}"
}

case_bad_optional_size() {
    local fixture_dir="${tmp_dir}/bad-optional"

    mkdir -p "${fixture_dir}"
    make_file "${fixture_dir}/flash.bin" 1048576
    make_file "${fixture_dir}/xbox_hdd.img" 16777216
    make_file "${fixture_dir}/mcpx.bin" 3

    env -i PATH="${PATH}" \
        XEMU_BROWSER_RUNTIME_MODE=real \
        XEMU_BROWSER_RUNTIME_FIXTURE_DIR="${fixture_dir}" \
            "${script}"
}

run_case bad-mode 2 'BROWSER_RUNTIME_SMOKE result=fail reason=bad-mode mode=bad-mode' case_bad_mode
run_case missing-real-flash 2 'BROWSER_RUNTIME_SMOKE result=fail reason=missing-env name=XEMU_FLASH' case_missing_real_flash
run_case missing-real-file 2 'BROWSER_RUNTIME_SMOKE result=fail reason=missing-file name=XEMU_FLASH' case_missing_real_file
run_case bad-optional-size 2 'BROWSER_RUNTIME_SMOKE result=fail reason=fixture-preflight status=2' case_bad_optional_size

bad_optional_out="${tmp_dir}/bad-optional-size.out"
if ! grep -q 'XEMU_MCPX must be 512 bytes' "${bad_optional_out}" ||
   ! grep -q 'BOOT_FIXTURE name=flash' "${bad_optional_out}"; then
    printf 'BROWSER_RUNTIME_SMOKE_SELFTEST case=bad-optional-size result=fail reason=missing-fixture-detail\n' >&2
    cat "${bad_optional_out}" >&2
    exit 1
fi

printf 'BROWSER_RUNTIME_SMOKE_SELFTEST_RESULT result=pass cases=4\n'
