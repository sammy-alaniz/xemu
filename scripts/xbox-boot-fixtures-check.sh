#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-fixtures-check.sh

Validates the private local Xbox boot fixtures referenced by environment
variables. The script prints only paths and sizes; it does not copy or inspect
fixture contents.

Required:
  XEMU_FLASH       Path to Xbox flash/BIOS image.

Optional:
  XEMU_MCPX        Path to MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM      Path to EEPROM image. Must be exactly 256 bytes.
  XEMU_HDD         Path to Xbox HDD image.
  XEMU_DVD         Path to optional DVD image.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

require_file() {
    local name="$1"
    local path="$2"

    if [ -z "${path}" ]; then
        echo "${name} is required" >&2
        exit 2
    fi

    if [ ! -f "${path}" ]; then
        echo "${name} does not exist: ${path}" >&2
        exit 2
    fi
}

validate_exact_size() {
    local name="$1"
    local path="$2"
    local expected="$3"
    local actual

    actual="$(file_size "${path}")"
    if [ "${actual}" != "${expected}" ]; then
        echo "${name} must be ${expected} bytes, got ${actual}: ${path}" >&2
        exit 2
    fi
}

validate_nonempty() {
    local name="$1"
    local path="$2"
    local actual

    actual="$(file_size "${path}")"
    if [ "${actual}" = "0" ]; then
        echo "${name} must be non-empty: ${path}" >&2
        exit 2
    fi
}

report_file() {
    local name="$1"
    local path="$2"
    local size

    size="$(file_size "${path}")"
    printf 'BOOT_FIXTURE name=%s size=%s path=%s\n' "${name}" "${size}" "${path}"
}

require_file "XEMU_FLASH" "${XEMU_FLASH:-}"
validate_nonempty "XEMU_FLASH" "${XEMU_FLASH}"
report_file "flash" "${XEMU_FLASH}"

if [ -n "${XEMU_MCPX:-}" ]; then
    require_file "XEMU_MCPX" "${XEMU_MCPX}"
    validate_exact_size "XEMU_MCPX" "${XEMU_MCPX}" 512
    report_file "mcpx" "${XEMU_MCPX}"
else
    printf 'BOOT_FIXTURE name=mcpx status=absent\n'
fi

if [ -n "${XEMU_EEPROM:-}" ]; then
    require_file "XEMU_EEPROM" "${XEMU_EEPROM}"
    validate_exact_size "XEMU_EEPROM" "${XEMU_EEPROM}" 256
    report_file "eeprom" "${XEMU_EEPROM}"
else
    printf 'BOOT_FIXTURE name=eeprom status=generated-by-smoke\n'
fi

if [ -n "${XEMU_HDD:-}" ]; then
    require_file "XEMU_HDD" "${XEMU_HDD}"
    validate_nonempty "XEMU_HDD" "${XEMU_HDD}"
    report_file "hdd" "${XEMU_HDD}"
else
    printf 'BOOT_FIXTURE name=hdd status=absent\n'
fi

if [ -n "${XEMU_DVD:-}" ]; then
    require_file "XEMU_DVD" "${XEMU_DVD}"
    report_file "dvd" "${XEMU_DVD}"
else
    printf 'BOOT_FIXTURE name=dvd status=absent\n'
fi

printf 'BOOT_FIXTURE_RESULT result=pass\n'
