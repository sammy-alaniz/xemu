#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-dashboard-section-map-evidence-check.sh [--require-context <context>] <log-file>

Validates the B6 XBE section-map diagnostic marker without treating it as
dashboard-loaded completion. The log must contain:

  BOOT_MARK b6 dashboard=xbe-section-map context=<context> status=ready ...
  BOOT_MARK b6 dashboard=xbe-section context=<context> ...

This proves the runtime emitted auditable XBE section metadata. It does not prove
dashboard execution; B6 still requires dashboard=xbe-executed plus native/browser
dashboard frame evidence.
EOF
}

require_context="browser-runtime"
log_path=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --require-context)
            require_context="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -n "${log_path}" ]; then
                printf 'DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=bad-arg value=%s\n' "$1" >&2
                exit 2
            fi
            log_path="$1"
            shift
            ;;
    esac
done

if [ -z "${log_path}" ]; then
    printf 'DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
    exit 2
fi

value_for() {
    local line="$1"
    local key="$2"
    local token

    for token in ${line}; do
        case "${token}" in
            "${key}="*)
                printf '%s' "${token#*=}"
                return
                ;;
        esac
    done
}

fail() {
    local reason="$1"
    shift || true

    printf 'DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=%s log=%s' \
        "${reason}" "${log_path}" >&2
    while [ "$#" -gt 0 ]; do
        printf ' %s' "$1" >&2
        shift
    done
    printf '\n' >&2
    exit 1
}

require_positive_int() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^[1-9][0-9]*$'; then
        fail "bad-${field}" "value=${value:-missing}"
    fi
}

require_nonnegative_int() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^[0-9]+$'; then
        fail "bad-${field}" "value=${value:-missing}"
    fi
}

require_hex() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
        fail "bad-${field}" "value=${value:-missing}"
    fi
}

require_yes_no() {
    local field="$1"
    local value="$2"

    case "${value}" in
        yes|no) ;;
        *) fail "bad-${field}" "value=${value:-missing}" ;;
    esac
}

latest_context_line() {
    local pattern="$1"
    local line
    local latest=""

    while IFS= read -r line; do
        if [ -n "${require_context}" ] &&
            [ "$(value_for "${line}" context)" != "${require_context}" ]; then
            continue
        fi
        latest="${line}"
    done < <(grep "${pattern}" "${log_path}" || true)

    printf '%s' "${latest}"
}

map_line="$(latest_context_line '^BOOT_MARK b6 dashboard=xbe-section-map ')"
if [ -z "${map_line}" ]; then
    fail missing-section-map-marker "context=${require_context:-any}"
fi

if [ "$(value_for "${map_line}" status)" != "ready" ]; then
    fail section-map-not-ready "status=$(value_for "${map_line}" status)"
fi

sections="$(value_for "${map_line}" sections)"
emitted="$(value_for "${map_line}" emitted)"
executable_sections="$(value_for "${map_line}" executable_sections)"
entry_section="$(value_for "${map_line}" entry_section)"
entry="$(value_for "${map_line}" entry)"
header_bytes="$(value_for "${map_line}" header_bytes)"
headers_size="$(value_for "${map_line}" headers_size)"
section_headers_addr="$(value_for "${map_line}" section_headers_addr)"
selected_phase="$(value_for "${map_line}" phase)"
if [ -z "${selected_phase}" ]; then
    selected_phase="loaded"
fi

case "${selected_phase}" in
    loaded|entry-ready) ;;
    *) fail bad-section-map-phase "phase=${selected_phase}" ;;
esac

require_positive_int sections "${sections}"
require_positive_int emitted "${emitted}"
require_positive_int executable-sections "${executable_sections}"
require_nonnegative_int entry-section "${entry_section}"
require_hex entry "${entry}"
require_hex section-headers-addr "${section_headers_addr}"
require_positive_int headers-size "${headers_size}"
require_positive_int header-bytes "${header_bytes}"

if [ "${emitted}" -gt "${sections}" ]; then
    fail emitted-exceeds-sections "emitted=${emitted}" "sections=${sections}"
fi

section_rows=0
entry_rows=0
executable_rows=0
mapped_entry_rows=0
mapped_start_rows=0

while IFS= read -r line; do
    if [ -n "${require_context}" ] &&
        [ "$(value_for "${line}" context)" != "${require_context}" ]; then
        continue
    fi

    line_phase="$(value_for "${line}" phase)"
    if [ -z "${line_phase}" ]; then
        line_phase="loaded"
    fi
    if [ "${line_phase}" != "${selected_phase}" ]; then
        continue
    fi

    index="$(value_for "${line}" index)"
    flags="$(value_for "${line}" flags)"
    executable="$(value_for "${line}" executable)"
    virtual_addr="$(value_for "${line}" virtual_addr)"
    virtual_size="$(value_for "${line}" virtual_size)"
    virtual_end="$(value_for "${line}" virtual_end)"
    raw_addr="$(value_for "${line}" raw_addr)"
    raw_size="$(value_for "${line}" raw_size)"
    contains_entry="$(value_for "${line}" contains_entry)"
    start_phys_mapped="$(value_for "${line}" start_phys_mapped)"
    start_phys="$(value_for "${line}" start_phys)"
    entry_phys_mapped="$(value_for "${line}" entry_phys_mapped)"
    entry_phys="$(value_for "${line}" entry_phys)"

    require_nonnegative_int section-index "${index}"
    require_hex section-flags "${flags}"
    require_yes_no section-executable "${executable}"
    require_hex section-virtual-addr "${virtual_addr}"
    require_positive_int section-virtual-size "${virtual_size}"
    require_hex section-virtual-end "${virtual_end}"
    require_hex section-raw-addr "${raw_addr}"
    require_nonnegative_int section-raw-size "${raw_size}"
    require_yes_no section-contains-entry "${contains_entry}"
    require_yes_no section-start-phys-mapped "${start_phys_mapped}"
    require_hex section-start-phys "${start_phys}"
    require_yes_no section-entry-phys-mapped "${entry_phys_mapped}"
    require_hex section-entry-phys "${entry_phys}"

    section_rows=$((section_rows + 1))
    if [ "${executable}" = "yes" ]; then
        executable_rows=$((executable_rows + 1))
    fi
    if [ "${contains_entry}" = "yes" ]; then
        entry_rows=$((entry_rows + 1))
        if [ "${entry_phys_mapped}" = "yes" ]; then
            mapped_entry_rows=$((mapped_entry_rows + 1))
        fi
    fi
    if [ "${start_phys_mapped}" = "yes" ]; then
        mapped_start_rows=$((mapped_start_rows + 1))
    fi
done < <(grep '^BOOT_MARK b6 dashboard=xbe-section ' "${log_path}" || true)

if [ "${section_rows}" -lt "${emitted}" ]; then
    fail missing-section-rows "rows=${section_rows}" "emitted=${emitted}"
fi

if [ "${entry_rows}" -lt 1 ]; then
    fail missing-entry-section-row
fi

if [ "${selected_phase}" = "entry-ready" ] && [ "${mapped_entry_rows}" -lt 1 ]; then
    fail missing-mapped-entry-section-row
fi

if [ "${executable_rows}" -lt 1 ]; then
    fail missing-executable-section-row
fi

if [ "${mapped_start_rows}" -lt 1 ]; then
    fail missing-mapped-section-start
fi

printf 'DASHBOARD_SECTION_MAP_EVIDENCE result=pass log=%s context=%s phase=%s sections=%s emitted=%s rows=%s executable_sections=%s executable_rows=%s entry_section=%s entry_rows=%s mapped_entry_rows=%s\n' \
    "${log_path}" "${require_context:-any}" "${selected_phase}" "${sections}" \
    "${emitted}" "${section_rows}" "${executable_sections}" \
    "${executable_rows}" "${entry_section}" "${entry_rows}" \
    "${mapped_entry_rows}"
