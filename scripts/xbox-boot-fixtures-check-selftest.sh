#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-fixtures-check-selftest.sh

Runs no-private-assets tests for xbox-boot-fixtures-check.sh. The tests create
temporary synthetic fixture files and verify that required-file and exact-size
guards fail or pass deterministically.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-fixtures-check-selftest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_file() {
    local path="$1"
    local size="$2"

    dd if=/dev/zero of="${path}" bs=1 count=0 seek="${size}" status=none
}

expect_pass() {
    local name="$1"
    shift

    if "$@" >"${tmp_dir}/${name}.out" 2>"${tmp_dir}/${name}.err"; then
        printf 'FIXTURE_SELFTEST case=%s result=pass\n' "${name}"
        return 0
    fi

    printf 'FIXTURE_SELFTEST case=%s result=fail reason=unexpected-failure\n' "${name}" >&2
    cat "${tmp_dir}/${name}.err" >&2
    return 1
}

expect_fail() {
    local name="$1"
    local expected="$2"
    shift 2

    if "$@" >"${tmp_dir}/${name}.out" 2>"${tmp_dir}/${name}.err"; then
        printf 'FIXTURE_SELFTEST case=%s result=fail reason=unexpected-pass\n' "${name}" >&2
        cat "${tmp_dir}/${name}.out" >&2
        return 1
    fi

    if ! grep -q "${expected}" "${tmp_dir}/${name}.err"; then
        printf 'FIXTURE_SELFTEST case=%s result=fail reason=missing-error expected=%s\n' \
            "${name}" "${expected}" >&2
        cat "${tmp_dir}/${name}.err" >&2
        return 1
    fi

    printf 'FIXTURE_SELFTEST case=%s result=pass\n' "${name}"
}

flash="${tmp_dir}/flash.bin"
mcpx="${tmp_dir}/mcpx.bin"
bad_mcpx="${tmp_dir}/bad-mcpx.bin"
eeprom="${tmp_dir}/eeprom.bin"
bad_eeprom="${tmp_dir}/bad-eeprom.bin"
empty_flash="${tmp_dir}/empty-flash.bin"
empty_hdd="${tmp_dir}/empty-hdd.img"
hdd="${tmp_dir}/xbox_hdd.img"
dvd="${tmp_dir}/dvd.iso"

make_file "${flash}" 1048576
make_file "${mcpx}" 512
make_file "${bad_mcpx}" 511
make_file "${eeprom}" 256
make_file "${bad_eeprom}" 255
make_file "${empty_flash}" 0
make_file "${empty_hdd}" 0
make_file "${hdd}" 16777216
make_file "${dvd}" 2048

expect_fail missing-flash "XEMU_FLASH is required" \
    env -i PATH="${PATH}" "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_fail missing-file "XEMU_FLASH does not exist" \
    env -i PATH="${PATH}" XEMU_FLASH="${tmp_dir}/missing.bin" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_fail empty-flash "XEMU_FLASH must be non-empty" \
    env -i PATH="${PATH}" XEMU_FLASH="${empty_flash}" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_fail bad-mcpx-size "XEMU_MCPX must be 512 bytes" \
    env -i PATH="${PATH}" XEMU_FLASH="${flash}" XEMU_MCPX="${bad_mcpx}" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_fail bad-eeprom-size "XEMU_EEPROM must be 256 bytes" \
    env -i PATH="${PATH}" XEMU_FLASH="${flash}" XEMU_EEPROM="${bad_eeprom}" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_fail empty-hdd "XEMU_HDD must be non-empty" \
    env -i PATH="${PATH}" XEMU_FLASH="${flash}" XEMU_HDD="${empty_hdd}" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

expect_pass complete-fixtures \
    env -i PATH="${PATH}" \
        XEMU_FLASH="${flash}" \
        XEMU_MCPX="${mcpx}" \
        XEMU_EEPROM="${eeprom}" \
        XEMU_HDD="${hdd}" \
        XEMU_DVD="${dvd}" \
        "${repo_root}/scripts/xbox-boot-fixtures-check.sh"

if ! grep -q 'BOOT_FIXTURE_RESULT result=pass' "${tmp_dir}/complete-fixtures.out"; then
    printf 'FIXTURE_SELFTEST case=complete-fixtures result=fail reason=missing-pass-marker\n' >&2
    cat "${tmp_dir}/complete-fixtures.out" >&2
    exit 1
fi

printf 'FIXTURE_SELFTEST_RESULT result=pass cases=7\n'
