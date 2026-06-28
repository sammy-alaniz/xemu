#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-real-fixtures-ready.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-real-fixtures-ready.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

run_case() {
    local name="$1"
    local expected="$2"
    local require_status="$3"
    local log_path="${tmp_dir}/${name}.log"
    shift 3

    if "$@" >"${log_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if ! grep -q "${expected}" "${log_path}"; then
        printf 'REAL_FIXTURE_READY_SELFTEST case=%s result=fail reason=missing-expected expected=%s log=%s\n' \
            "${name}" "${expected}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    if [ "${require_status}" != "*" ] && [ "${status}" != "${require_status}" ]; then
        printf 'REAL_FIXTURE_READY_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s log=%s\n' \
            "${name}" "${require_status}" "${status}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    cat "${log_path}"
    printf 'REAL_FIXTURE_READY_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

expect_case_detail() {
    local name="$1"
    local pattern="$2"
    local log_path="${tmp_dir}/${name}.log"

    if ! grep -q "${pattern}" "${log_path}"; then
        printf 'REAL_FIXTURE_READY_SELFTEST case=%s result=fail reason=missing-detail expected=%s log=%s\n' \
            "${name}" "${pattern}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi
}

missing_env() {
    env -i PATH="${PATH}" XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 "${script}"
}

missing_env_require() {
    env -i PATH="${PATH}" \
        XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 \
        XEMU_REAL_FIXTURE_READY_REQUIRE=1 \
            "${script}"
}

missing_fixture_dir() {
    local dir="${tmp_dir}/missing-fixture-dir"

    mkdir -p "${dir}"
    env -i PATH="${PATH}" XEMU_REAL_B3_FIXTURE_DIR="${dir}" "${script}"
}

bad_optional() {
    local dir="${tmp_dir}/bad-optional"

    mkdir -p "${dir}"
    printf 'flash' >"${dir}/flash.bin"
    printf 'hdd' >"${dir}/xbox_hdd.img"
    printf 'bad' >"${dir}/mcpx.bin"

    env -i PATH="${PATH}" XEMU_REAL_B3_FIXTURE_DIR="${dir}" "${script}"
}

empty_required() {
    local dir="${tmp_dir}/empty-required"

    mkdir -p "${dir}"
    : >"${dir}/flash.bin"
    printf 'hdd' >"${dir}/xbox_hdd.img"

    env -i PATH="${PATH}" XEMU_REAL_B3_FIXTURE_DIR="${dir}" "${script}"
}

pass_autodetect() {
    local dir="${tmp_dir}/pass"

    mkdir -p "${dir}"
    printf 'flash' >"${dir}/flash.bin"
    printf 'hdd' >"${dir}/xbox_hdd.img"
    dd if=/dev/zero of="${dir}/mcpx.bin" bs=512 count=1 >/dev/null 2>&1
    dd if=/dev/zero of="${dir}/eeprom.bin" bs=256 count=1 >/dev/null 2>&1

    env -i PATH="${PATH}" XEMU_REAL_B3_FIXTURE_DIR="${dir}" "${script}"
}

pass_explicit_env() {
    local dir="${tmp_dir}/explicit"

    mkdir -p "${dir}"
    printf 'flash' >"${dir}/custom-flash.bin"
    printf 'hdd' >"${dir}/custom-hdd.img"

    env -i PATH="${PATH}" \
        XEMU_FLASH="${dir}/custom-flash.bin" \
        XEMU_HDD="${dir}/custom-hdd.img" \
            "${script}"
}

run_case missing 'REAL_FIXTURE_READY_RESULT result=missing-required' 0 missing_env
run_case missing-require 'REAL_FIXTURE_READY_RESULT result=missing-required' 2 missing_env_require
run_case missing-fixture-dir 'REAL_FIXTURE_READY_RESULT result=missing-required' 0 missing_fixture_dir
expect_case_detail missing-fixture-dir 'REAL_FIXTURE_READY item=flash status=missing source=fixture-dir path=.*/missing-fixture-dir/flash.bin'
expect_case_detail missing-fixture-dir 'REAL_FIXTURE_READY item=hdd status=missing source=fixture-dir path=.*/missing-fixture-dir/xbox_hdd.img'
run_case bad-optional 'REAL_FIXTURE_READY_RESULT result=fail' 0 bad_optional
run_case empty-required 'REAL_FIXTURE_READY_RESULT result=fail' 0 empty_required
run_case pass-autodetect 'REAL_FIXTURE_READY_RESULT result=pass' 0 pass_autodetect
expect_case_detail pass-autodetect 'REAL_FIXTURE_READY item=flash status=present source=fixture-dir'
expect_case_detail pass-autodetect 'REAL_FIXTURE_READY item=mcpx status=present source=fixture-dir bytes=512'
run_case pass-explicit-env 'REAL_FIXTURE_READY_RESULT result=pass' 0 pass_explicit_env
expect_case_detail pass-explicit-env 'REAL_FIXTURE_READY item=flash status=present source=env'
expect_case_detail pass-explicit-env 'REAL_FIXTURE_READY item=hdd status=present source=env'

printf 'REAL_FIXTURE_READY_SELFTEST_RESULT result=pass cases=7\n'
