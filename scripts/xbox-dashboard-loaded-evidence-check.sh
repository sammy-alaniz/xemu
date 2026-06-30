#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-dashboard-loaded-evidence-check.sh <log-file>

Validates the B6 dashboard-loaded evidence contract without requiring private
assets. The log must contain all of:

  BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=<name>.xbe ...
      - or -
  BOOT_MARK b6 dashboard=xbe-read-complete context=browser-runtime \
      complete XBE image read progress ...
  BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime \
      guest_addr=0x... source=virtual-header ...
  BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime \
      status=ready entry_code_read=yes phys_match=yes ...
  BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime \
      guest_pc=0x... phys_match=yes section_flags=0x... ...
  NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless \
      source=native-framebuffer hash=<hex> width=<n> height=<n> \
      dashboard=xbe-executed ...
  BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes \
      hash=<hex> native_hash=<hex> source=browser-framebuffer width=<n> height=<n>

Each B6 marker must include context=browser-runtime. This script does not
generate dashboard evidence. It prevents weak signals, such as a non-empty B4
scanout alone or native-only dashboard progress, from satisfying B6.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

log_path="${1:-}"

if [ -z "${log_path}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-log-arg\n' >&2
    exit 2
fi

if [ ! -f "${log_path}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-log path=%s\n' "${log_path}" >&2
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

require_marker() {
    local kind="$1"
    local reason="$2"
    local line

    line="$(grep "^BOOT_MARK b6 dashboard=${kind} " "${log_path}" | tail -n 1 || true)"
    if [ -z "${line}" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=%s log=%s\n' \
            "${reason}" "${log_path}" >&2
        exit 1
    fi

    printf '%s' "${line}"
}

read_line="$(grep '^BOOT_MARK b6 dashboard=xbe-read ' "${log_path}" | tail -n 1 || true)"
read_kind="fatx-file"
if [ -z "${read_line}" ]; then
    read_line="$(grep '^BOOT_MARK b6 dashboard=xbe-read-complete ' "${log_path}" | tail -n 1 || true)"
    read_kind="read-complete"
fi
if [ -z "${read_line}" ]; then
    read_progress_line="$(grep '^BOOT_MARK b6 dashboard=xbe-read-progress ' "${log_path}" | tail -n 1 || true)"
    if [ -n "${read_progress_line}" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-complete-marker log=%s\n' \
            "${log_path}" >&2
        exit 1
    fi
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker log=%s\n' \
        "${log_path}" >&2
    exit 1
fi
loaded_line="$(require_marker xbe-loaded missing-xbe-loaded-marker)"
entry_ready_line="$(grep '^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready' "${log_path}" | tail -n 1 || true)"
if [ -z "${entry_ready_line}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-entry-ready-marker log=%s\n' \
        "${log_path}" >&2
    exit 1
fi

executed_line="$(require_marker xbe-executed missing-xbe-executed-marker)"

require_context() {
    local marker="$1"
    local value="$2"

    if [ "${value}" != "browser-runtime" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-%s-context value=%s log=%s\n' \
            "${marker}" "${value:-missing}" "${log_path}" >&2
        exit 1
    fi
}

read_context="$(value_for "${read_line}" context)"
loaded_context="$(value_for "${loaded_line}" context)"
entry_ready_context="$(value_for "${entry_ready_line}" context)"
executed_context="$(value_for "${executed_line}" context)"

require_context xbe-read "${read_context}"
require_context xbe-loaded "${loaded_context}"
require_context xbe-entry-ready "${entry_ready_context}"
require_context xbe-executed "${executed_context}"

require_positive_int() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^[1-9][0-9]*$'; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-%s value=%s log=%s\n' \
            "${field}" "${value:-missing}" "${log_path}" >&2
        exit 1
    fi
}

require_nonnegative_int() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^[0-9]+$'; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-%s value=%s log=%s\n' \
            "${field}" "${value:-missing}" "${log_path}" >&2
        exit 1
    fi
}

require_hex() {
    local field="$1"
    local value="$2"

    if ! printf '%s' "${value}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-%s value=%s log=%s\n' \
            "${field}" "${value:-missing}" "${log_path}" >&2
        exit 1
    fi
}

if [ "${read_kind}" = "fatx-file" ]; then
    xbe_file="$(value_for "${read_line}" file)"
    if ! printf '%s' "${xbe_file}" | grep -Eiq '\.xbe$'; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-file value=%s log=%s\n' \
            "${xbe_file:-missing}" "${log_path}" >&2
        exit 1
    fi

    start_lba="$(value_for "${read_line}" start_lba)"
    sectors_value="$(value_for "${read_line}" sectors)"
    file_size="$(value_for "${read_line}" file_size)"
    read_lba="$(value_for "${read_line}" read_lba)"
    read_nsectors="$(value_for "${read_line}" read_nsectors)"
    overlap_lba="$(value_for "${read_line}" overlap_lba)"
    overlap_sectors="$(value_for "${read_line}" overlap_sectors)"
    read_source="$(value_for "${read_line}" source)"

    require_nonnegative_int start-lba "${start_lba}"
    require_positive_int sectors "${sectors_value}"
    require_positive_int file-size "${file_size}"
    require_nonnegative_int read-lba "${read_lba}"
    require_positive_int read-nsectors "${read_nsectors}"
    require_nonnegative_int overlap-lba "${overlap_lba}"
    require_positive_int overlap-sectors "${overlap_sectors}"

    if [ "${read_source}" != "ide-read-log" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-read-source value=%s log=%s\n' \
            "${read_source:-missing}" "${log_path}" >&2
        exit 1
    fi
else
    xbe_file="read-complete"
    start_lba="$(value_for "${read_line}" start_lba)"
    expected_sectors="$(value_for "${read_line}" expected_sectors)"
    contiguous_bytes="$(value_for "${read_line}" contiguous_bytes)"
    image_size="$(value_for "${read_line}" image_size)"
    read_source="$(value_for "${read_line}" source)"
    read_status="$(value_for "${read_line}" status)"
    read_sig="$(value_for "${read_line}" sig)"
    read_guest_addr="$(value_for "${read_line}" guest_addr)"

    require_nonnegative_int start-lba "${start_lba}"
    require_positive_int expected-sectors "${expected_sectors}"
    require_positive_int contiguous-bytes "${contiguous_bytes}"
    require_positive_int read-image-size "${image_size}"

    if [ "${read_source}" != "ide-dma-read-complete" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-read-source value=%s log=%s\n' \
            "${read_source:-missing}" "${log_path}" >&2
        exit 1
    fi

    if [ "${read_status}" != "xbeh-present" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-read-status value=%s log=%s\n' \
            "${read_status:-missing}" "${log_path}" >&2
        exit 1
    fi

    if [ "${read_sig}" != "0x48454258" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-read-sig value=%s log=%s\n' \
            "${read_sig:-missing}" "${log_path}" >&2
        exit 1
    fi

    if ! printf '%s' "${read_guest_addr}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-read-guest-addr value=%s log=%s\n' \
            "${read_guest_addr:-missing}" "${log_path}" >&2
        exit 1
    fi

    if [ "${contiguous_bytes}" -lt "${image_size}" ]; then
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=incomplete-xbe-read value=%s expected=%s log=%s\n' \
            "${contiguous_bytes}" "${image_size}" "${log_path}" >&2
        exit 1
    fi
fi

guest_addr="$(value_for "${loaded_line}" guest_addr)"
if ! printf '%s' "${guest_addr}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-guest-addr value=%s log=%s\n' \
        "${guest_addr:-missing}" "${log_path}" >&2
    exit 1
fi

loaded_source="$(value_for "${loaded_line}" source)"
if [ "${loaded_source}" != "virtual-header" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-xbe-loaded-source value=%s log=%s\n' \
        "${loaded_source:-missing}" "${log_path}" >&2
    exit 1
fi

entry_code_read="$(value_for "${entry_ready_line}" entry_code_read)"
entry_phys_match="$(value_for "${entry_ready_line}" phys_match)"
guest_entry="$(value_for "${entry_ready_line}" guest_entry)"
entry_phys="$(value_for "${entry_ready_line}" entry_phys)"

if [ "${entry_code_read}" != "yes" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=entry-code-unreadable value=%s log=%s\n' \
        "${entry_code_read:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${entry_phys_match}" != "yes" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=entry-phys-mismatch value=%s log=%s\n' \
        "${entry_phys_match:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${guest_entry}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-guest-entry value=%s log=%s\n' \
        "${guest_entry:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${entry_phys}" | grep -Eq '^0x[0-9a-fA-F]+$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-entry-phys value=%s log=%s\n' \
        "${entry_phys:-missing}" "${log_path}" >&2
    exit 1
fi

guest_pc="$(value_for "${executed_line}" guest_pc)"
executed_phys_match="$(value_for "${executed_line}" phys_match)"
executed_section_index="$(value_for "${executed_line}" section_index)"
executed_section_flags="$(value_for "${executed_line}" section_flags)"
executed_section_start="$(value_for "${executed_line}" section_virtual_addr)"
executed_section_end="$(value_for "${executed_line}" section_virtual_end)"

require_hex guest-pc "${guest_pc}"
if [ "${executed_phys_match}" != "yes" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=executed-phys-mismatch value=%s log=%s\n' \
        "${executed_phys_match:-missing}" "${log_path}" >&2
    exit 1
fi
require_nonnegative_int section-index "${executed_section_index}"
require_hex section-flags "${executed_section_flags}"
require_hex section-virtual-addr "${executed_section_start}"
require_hex section-virtual-end "${executed_section_end}"
if [ $((executed_section_flags & 0x4)) -eq 0 ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=section-not-executable value=%s log=%s\n' \
        "${executed_section_flags}" "${log_path}" >&2
    exit 1
fi

capture_line="$(grep '^BROWSER_DASHBOARD_CAPTURE ' "${log_path}" | tail -n 1 || true)"
if [ -z "${capture_line}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-dashboard-capture log=%s\n' \
        "${log_path}" >&2
    exit 1
fi

capture_result="$(value_for "${capture_line}" result)"
native_ref_match="$(value_for "${capture_line}" native_ref_match)"
hash_value="$(value_for "${capture_line}" hash)"
native_hash="$(value_for "${capture_line}" native_hash)"
source_value="$(value_for "${capture_line}" source)"
width_value="$(value_for "${capture_line}" width)"
height_value="$(value_for "${capture_line}" height)"

if [ "${capture_result}" != "pass" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=capture-not-pass value=%s log=%s\n' \
        "${capture_result:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${native_ref_match}" != "yes" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=native-ref-mismatch value=%s log=%s\n' \
        "${native_ref_match:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${hash_value}" | grep -Eq '^[0-9a-fA-F]{16,128}$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-hash value=%s log=%s\n' \
        "${hash_value:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${native_hash}" | grep -Eq '^[0-9a-fA-F]{16,128}$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-hash value=%s log=%s\n' \
        "${native_hash:-missing}" "${log_path}" >&2
    exit 1
fi

case "${source_value}" in
    browser-canvas|browser-framebuffer) ;;
    *)
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-source value=%s log=%s\n' \
            "${source_value:-missing}" "${log_path}" >&2
        exit 1
        ;;
esac

if ! printf '%s' "${width_value}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-width value=%s log=%s\n' \
        "${width_value:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${height_value}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-height value=%s log=%s\n' \
        "${height_value:-missing}" "${log_path}" >&2
    exit 1
fi

native_reference_line="$(grep '^NATIVE_DASHBOARD_REFERENCE ' "${log_path}" | tail -n 1 || true)"
if [ -z "${native_reference_line}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-native-reference log=%s\n' \
        "${log_path}" >&2
    exit 1
fi

native_reference_result="$(value_for "${native_reference_line}" result)"
native_reference_context="$(value_for "${native_reference_line}" context)"
native_reference_source="$(value_for "${native_reference_line}" source)"
native_reference_hash="$(value_for "${native_reference_line}" hash)"
native_reference_width="$(value_for "${native_reference_line}" width)"
native_reference_height="$(value_for "${native_reference_line}" height)"
native_reference_dashboard="$(value_for "${native_reference_line}" dashboard)"

if [ "${native_reference_result}" != "pass" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=native-reference-not-pass value=%s log=%s\n' \
        "${native_reference_result:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${native_reference_context}" != "native-headless" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-context value=%s log=%s\n' \
        "${native_reference_context:-missing}" "${log_path}" >&2
    exit 1
fi

case "${native_reference_source}" in
    native-framebuffer|native-screenshot) ;;
    *)
        printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-source value=%s log=%s\n' \
            "${native_reference_source:-missing}" "${log_path}" >&2
        exit 1
        ;;
esac

if ! printf '%s' "${native_reference_hash}" | grep -Eq '^[0-9a-fA-F]{16,128}$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-hash value=%s log=%s\n' \
        "${native_reference_hash:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${native_reference_hash}" != "${native_hash}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=native-reference-hash-mismatch value=%s expected=%s log=%s\n' \
        "${native_hash:-missing}" "${native_reference_hash}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${native_reference_width}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-width value=%s log=%s\n' \
        "${native_reference_width:-missing}" "${log_path}" >&2
    exit 1
fi

if ! printf '%s' "${native_reference_height}" | grep -Eq '^[1-9][0-9]*$'; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-height value=%s log=%s\n' \
        "${native_reference_height:-missing}" "${log_path}" >&2
    exit 1
fi

if [ "${native_reference_width}" != "${width_value}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=native-reference-width-mismatch value=%s expected=%s log=%s\n' \
        "${width_value:-missing}" "${native_reference_width}" "${log_path}" >&2
    exit 1
fi

if [ "${native_reference_height}" != "${height_value}" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=native-reference-height-mismatch value=%s expected=%s log=%s\n' \
        "${height_value:-missing}" "${native_reference_height}" "${log_path}" >&2
    exit 1
fi

if [ "${native_reference_dashboard}" != "xbe-executed" ]; then
    printf 'DASHBOARD_LOADED_EVIDENCE result=fail reason=bad-native-reference-dashboard value=%s log=%s\n' \
        "${native_reference_dashboard:-missing}" "${log_path}" >&2
    exit 1
fi

printf 'DASHBOARD_LOADED_EVIDENCE result=pass log=%s file=%s guest_addr=%s guest_entry=%s guest_pc=%s hash=%s native_hash=%s source=%s native_reference_source=%s\n' \
    "${log_path}" "${xbe_file}" "${guest_addr}" "${guest_entry}" \
    "${guest_pc}" "${hash_value}" "${native_hash}" "${source_value}" \
    "${native_reference_source}"
