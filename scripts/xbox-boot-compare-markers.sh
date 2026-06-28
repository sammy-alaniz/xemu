#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-compare-markers.sh <baseline.log> <candidate.log>

Compares BOOT_MARK milestone sequences from two Xbox boot smoke logs. The
comparison intentionally ignores full log noise and can compare either marker
sets or exact marker order through the requested B-level.

Optional controls:
  XEMU_COMPARE_MIN_LEVEL   Required and compared B-level scope. Default: B0.
  XEMU_COMPARE_STRICT_ORDER Compare marker order exactly when set to 1.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -ne 2 ]; then
    usage
    if [ "$#" -eq 2 ]; then
        exit 0
    fi
    exit 2
fi

baseline_log="$1"
candidate_log="$2"
min_level="${XEMU_COMPARE_MIN_LEVEL:-B0}"

level_value() {
    case "$1" in
        B0|b0) echo 0 ;;
        B1|b1) echo 1 ;;
        B2|b2) echo 2 ;;
        B3|b3) echo 3 ;;
        B4|b4) echo 4 ;;
        B5|b5) echo 5 ;;
        *)
            echo "Unknown boot level '$1'" >&2
            exit 2
            ;;
    esac
}

require_file() {
    local name="$1"
    local path="$2"

    if [ ! -f "${path}" ]; then
        echo "${name} does not exist: ${path}" >&2
        exit 2
    fi
}

extract_markers() {
    sed -n 's/^BOOT_MARK //p' "$1"
}

extract_markers_through_level() {
    local log="$1"
    local max_value="$2"
    local line
    local level
    local value

    while IFS= read -r line; do
        level="${line%% *}"
        value="$(level_value "${level}")"
        if [ "${value}" -le "${max_value}" ]; then
            printf '%s\n' "${line}"
        fi
    done < <(extract_markers "${log}")
}

highest_level_value() {
    local log="$1"
    local highest=-1
    local level
    local value

    for level in b0 b1 b2 b3 b4 b5; do
        if grep -q "^BOOT_MARK ${level}" "${log}"; then
            value="$(level_value "${level}")"
            highest="${value}"
        fi
    done

    echo "${highest}"
}

require_file "baseline log" "${baseline_log}"
require_file "candidate log" "${candidate_log}"

baseline_markers="$(mktemp)"
candidate_markers="$(mktemp)"
baseline_compare="$(mktemp)"
candidate_compare="$(mktemp)"
diff_log="$(mktemp)"
trap 'rm -f "${baseline_markers}" "${candidate_markers}" "${baseline_compare}" "${candidate_compare}" "${diff_log}"' EXIT

extract_markers "${baseline_log}" >"${baseline_markers}"
extract_markers "${candidate_log}" >"${candidate_markers}"

if [ ! -s "${baseline_markers}" ]; then
    echo "baseline has no BOOT_MARK lines: ${baseline_log}" >&2
    exit 1
fi

if [ ! -s "${candidate_markers}" ]; then
    echo "candidate has no BOOT_MARK lines: ${candidate_log}" >&2
    exit 1
fi

min_value="$(level_value "${min_level}")"
baseline_highest="$(highest_level_value "${baseline_log}")"
candidate_highest="$(highest_level_value "${candidate_log}")"
extract_markers_through_level "${baseline_log}" "${min_value}" >"${baseline_markers}"
extract_markers_through_level "${candidate_log}" "${min_value}" >"${candidate_markers}"

result="pass"
if [ "${baseline_highest}" -lt "${min_value}" ]; then
    result="fail"
fi
if [ "${candidate_highest}" -lt "${min_value}" ]; then
    result="fail"
fi

compare_mode="set"
if [ "${XEMU_COMPARE_STRICT_ORDER:-0}" = "1" ]; then
    compare_mode="strict-order"
    cp "${baseline_markers}" "${baseline_compare}"
    cp "${candidate_markers}" "${candidate_compare}"
else
    LC_ALL=C sort "${baseline_markers}" >"${baseline_compare}"
    LC_ALL=C sort "${candidate_markers}" >"${candidate_compare}"
fi

if ! diff -u "${baseline_compare}" "${candidate_compare}" >"${diff_log}"; then
    result="fail"
fi

printf 'BOOT_MARK_COMPARE result=%s mode=%s baseline=B%s candidate=B%s expected=%s baseline_log=%s candidate_log=%s\n' \
    "${result}" "${compare_mode}" "${baseline_highest}" "${candidate_highest}" "${min_level}" \
    "${baseline_log}" "${candidate_log}"

if [ -s "${diff_log}" ]; then
    cat "${diff_log}"
fi

if [ "${result}" != "pass" ]; then
    exit 1
fi
