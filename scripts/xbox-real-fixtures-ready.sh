#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-fixtures-ready.sh

Reports whether private local Xbox fixtures are ready for the real B3 matrix.
This script never starts emulation and does not inspect fixture contents beyond
path existence and size checks.

Required for real B3:
  XEMU_FLASH       Path to Xbox flash/BIOS image, or flash.bin in a fixture dir.
  XEMU_HDD         Path to Xbox HDD image, or xbox_hdd.img in a fixture dir.

Optional:
  XEMU_MCPX        Path to MCPX boot ROM. Must be exactly 512 bytes.
  XEMU_EEPROM      Path to EEPROM image. Must be exactly 256 bytes.
  XEMU_DVD         Path to optional DVD image.

Controls:
  XEMU_REAL_B3_FIXTURE_DIR          Optional fixture dir for auto-discovery.
  XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS Ignore fixtures/ and xemu-fixtures/ when set to 1.
  XEMU_REAL_FIXTURE_READY_REQUIRE   Exit nonzero unless result=pass when set to 1.

Auto-discovery checks:
  $XEMU_REAL_B3_FIXTURE_DIR, fixtures/, xemu-fixtures/
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fixture_dir="${XEMU_REAL_B3_FIXTURE_DIR:-}"
ignore_repo_dirs="${XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS:-0}"
require_pass="${XEMU_REAL_FIXTURE_READY_REQUIRE:-0}"

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

value_for_env_or_discovered() {
    local env_name="$1"
    local file_name="$2"
    local candidate_dir
    local candidate_path

    if [ -n "${!env_name:-}" ]; then
        printf '%s' "${!env_name}"
        return
    fi

    for candidate_dir in "${fixture_dir}"; do
        if [ -z "${candidate_dir}" ]; then
            continue
        fi
        candidate_path="${candidate_dir}/${file_name}"
        if [ -f "${candidate_path}" ]; then
            printf '%s' "${candidate_path}"
            return
        fi
    done
    if [ "${ignore_repo_dirs}" = "1" ]; then
        return
    fi
    for candidate_dir in "${repo_root}/fixtures" "${repo_root}/xemu-fixtures"; do
        candidate_path="${candidate_dir}/${file_name}"
        if [ -f "${candidate_path}" ]; then
            printf '%s' "${candidate_path}"
            return
        fi
    done
}

expected_path_for_existing_fixture_dir() {
    local env_name="$1"
    local file_name="$2"
    local candidate_dir

    if [ -n "${!env_name:-}" ]; then
        return
    fi

    for candidate_dir in "${fixture_dir}"; do
        if [ -z "${candidate_dir}" ] || [ ! -d "${candidate_dir}" ]; then
            continue
        fi
        printf '%s/%s' "${candidate_dir}" "${file_name}"
        return
    done
    if [ "${ignore_repo_dirs}" = "1" ]; then
        return
    fi
    for candidate_dir in "${repo_root}/fixtures" "${repo_root}/xemu-fixtures"; do
        if [ ! -d "${candidate_dir}" ]; then
            continue
        fi
        printf '%s/%s' "${candidate_dir}" "${file_name}"
        return
    done
}

source_for_path() {
    local env_name="$1"
    local file_name="$2"
    local path="$3"

    if [ -z "${path}" ]; then
        printf 'not-found'
        return
    fi
    if [ -n "${!env_name:-}" ] && [ "${!env_name}" = "${path}" ]; then
        printf 'env'
        return
    fi
    if [ -n "${fixture_dir}" ] && [ "${fixture_dir}/${file_name}" = "${path}" ]; then
        printf 'fixture-dir'
        return
    fi
    if [ "${repo_root}/fixtures/${file_name}" = "${path}" ]; then
        printf 'fixtures'
        return
    fi
    if [ "${repo_root}/xemu-fixtures/${file_name}" = "${path}" ]; then
        printf 'xemu-fixtures'
        return
    fi

    printf 'unknown'
}

report_required_file() {
    local item="$1"
    local path="$2"
    local source="$3"
    local size

    if [ -z "${path}" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=missing source=%s\n' "${item}" "${source}"
        return 1
    fi
    if [ ! -f "${path}" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=missing source=%s path=%s\n' "${item}" "${source}" "${path}"
        return 1
    fi

    size="$(file_size "${path}")"
    if [ "${size}" = "0" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=empty source=%s path=%s\n' "${item}" "${source}" "${path}"
        return 2
    fi

    printf 'REAL_FIXTURE_READY item=%s status=present source=%s bytes=%s path=%s\n' \
        "${item}" "${source}" "${size}" "${path}"
}

report_optional_file() {
    local item="$1"
    local path="$2"
    local expected_size="${3:-}"
    local source="${4:-not-found}"
    local size

    if [ -z "${path}" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=absent source=%s\n' "${item}" "${source}"
        return 0
    fi
    if [ ! -f "${path}" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=missing source=%s path=%s\n' "${item}" "${source}" "${path}"
        return 1
    fi

    size="$(file_size "${path}")"
    if [ -n "${expected_size}" ] && [ "${size}" != "${expected_size}" ]; then
        printf 'REAL_FIXTURE_READY item=%s status=bad-size source=%s expected=%s bytes=%s path=%s\n' \
            "${item}" "${source}" "${expected_size}" "${size}" "${path}"
        return 1
    fi

    printf 'REAL_FIXTURE_READY item=%s status=present source=%s bytes=%s path=%s\n' \
        "${item}" "${source}" "${size}" "${path}"
}

flash_path="$(value_for_env_or_discovered XEMU_FLASH flash.bin)"
hdd_path="$(value_for_env_or_discovered XEMU_HDD xbox_hdd.img)"
mcpx_path="$(value_for_env_or_discovered XEMU_MCPX mcpx.bin)"
eeprom_path="$(value_for_env_or_discovered XEMU_EEPROM eeprom.bin)"
dvd_path="$(value_for_env_or_discovered XEMU_DVD dvd.iso)"
if [ -z "${flash_path}" ]; then
    flash_path="$(expected_path_for_existing_fixture_dir XEMU_FLASH flash.bin)"
fi
if [ -z "${hdd_path}" ]; then
    hdd_path="$(expected_path_for_existing_fixture_dir XEMU_HDD xbox_hdd.img)"
fi
flash_source="$(source_for_path XEMU_FLASH flash.bin "${flash_path}")"
hdd_source="$(source_for_path XEMU_HDD xbox_hdd.img "${hdd_path}")"
mcpx_source="$(source_for_path XEMU_MCPX mcpx.bin "${mcpx_path}")"
eeprom_source="$(source_for_path XEMU_EEPROM eeprom.bin "${eeprom_path}")"
dvd_source="$(source_for_path XEMU_DVD dvd.iso "${dvd_path}")"

missing_required=0
invalid_required=0
invalid_optional=0

report_required_file flash "${flash_path}" "${flash_source}" || {
    status="$?"
    if [ "${status}" = "2" ]; then
        invalid_required=1
    else
        missing_required=1
    fi
}
report_required_file hdd "${hdd_path}" "${hdd_source}" || {
    status="$?"
    if [ "${status}" = "2" ]; then
        invalid_required=1
    else
        missing_required=1
    fi
}
report_optional_file mcpx "${mcpx_path}" 512 "${mcpx_source}" || invalid_optional=1
report_optional_file eeprom "${eeprom_path}" 256 "${eeprom_source}" || invalid_optional=1
report_optional_file dvd "${dvd_path}" "" "${dvd_source}" || invalid_optional=1

if [ "${missing_required}" = "1" ]; then
    result="missing-required"
    next="add-fixtures"
elif [ "${invalid_required}" = "1" ] || [ "${invalid_optional}" = "1" ]; then
    result="fail"
    next="fix-fixtures"
else
    result="pass"
    next="real-b3-preflight"
fi

printf 'REAL_FIXTURE_READY_RESULT result=%s next=%s require=%s\n' \
    "${result}" "${next}" "${require_pass}"

if [ "${require_pass}" = "1" ] && [ "${result}" != "pass" ]; then
    exit 2
fi
