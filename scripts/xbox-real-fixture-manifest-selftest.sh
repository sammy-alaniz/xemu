#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-real-fixture-manifest.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-real-fixture-manifest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

run_case() {
    local name="$1"
    local expected="$2"
    local expected_status="$3"
    local log_path="${tmp_dir}/${name}.log"
    shift 3

    if "$@" >"${log_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if ! grep -q "${expected}" "${log_path}"; then
        printf 'REAL_FIXTURE_MANIFEST_SELFTEST case=%s result=fail reason=missing-expected expected=%s log=%s\n' \
            "${name}" "${expected}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'REAL_FIXTURE_MANIFEST_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s log=%s\n' \
            "${name}" "${expected_status}" "${status}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    cat "${log_path}"
    printf 'REAL_FIXTURE_MANIFEST_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

missing_case() {
    env -i PATH="${PATH}" \
        XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 \
            "${script}" "${tmp_dir}/missing"
}

missing_require_case() {
    env -i PATH="${PATH}" \
        XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 \
        XEMU_REAL_FIXTURE_MANIFEST_REQUIRE=1 \
            "${script}" "${tmp_dir}/missing-require"
}

pass_case() {
    local fixture_dir="${tmp_dir}/fixtures"

    mkdir -p "${fixture_dir}"
    printf 'flash' >"${fixture_dir}/flash.bin"
    printf 'hdd' >"${fixture_dir}/xbox_hdd.img"
    dd if=/dev/zero of="${fixture_dir}/mcpx.bin" bs=512 count=1 >/dev/null 2>&1
    dd if=/dev/zero of="${fixture_dir}/eeprom.bin" bs=256 count=1 >/dev/null 2>&1

    env -i PATH="${PATH}" \
        XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
            "${script}" "${tmp_dir}/pass"
}

run_case missing 'REAL_FIXTURE_MANIFEST_RESULT result=missing-required' 0 missing_case
run_case missing-require 'REAL_FIXTURE_MANIFEST_RESULT result=missing-required' 2 missing_require_case
run_case pass 'REAL_FIXTURE_MANIFEST_RESULT result=pass' 0 pass_case

if ! grep -q 'This manifest is a no-emulation handoff artifact' "${tmp_dir}/pass/real-fixture-manifest.md"; then
    printf 'REAL_FIXTURE_MANIFEST_SELFTEST case=manifest-doc result=fail reason=missing-manifest-text\n' >&2
    exit 1
fi

printf 'REAL_FIXTURE_MANIFEST_SELFTEST_RESULT result=pass cases=3\n'
