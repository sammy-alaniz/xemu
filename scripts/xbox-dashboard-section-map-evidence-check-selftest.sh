#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-dashboard-section-map-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-dashboard-section-map.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local log_path="${tmp_dir}/${name}.log"
    local out_path="${tmp_dir}/${name}.out"
    local status
    shift 3

    "$@" >"${log_path}"

    if "${script}" "${log_path}" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'DASHBOARD_SECTION_MAP_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'DASHBOARD_SECTION_MAP_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'DASHBOARD_SECTION_MAP_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

valid_map() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=ready sections=2 emitted=2 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
}

valid_sections() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=yes entry_phys=0x000c7d60 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

loaded_unmapped_sections() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

entry_ready_map() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=ready phase=entry-ready sections=2 emitted=2 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
}

entry_ready_sections() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime phase=entry-ready index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=yes entry_phys=0x000c7d60 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime phase=entry-ready index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

valid_contract() {
    valid_map
    valid_sections
}

valid_loaded_unmapped_contract() {
    valid_map
    loaded_unmapped_sections
}

valid_entry_ready_contract() {
    valid_map
    loaded_unmapped_sections
    entry_ready_map
    entry_ready_sections
}

case_missing_map() {
    valid_sections
}

case_invalid_map() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=invalid reason=section-table-outside-headers sections=2 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
    valid_sections
}

case_bad_context() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=native-headless status=ready sections=2 emitted=2 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=native-headless index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=yes entry_phys=0x000c7d60 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=native-headless index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

case_missing_entry_row() {
    valid_map
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

case_missing_executable_row() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=ready sections=2 emitted=2 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=0 flags=0x00000002 executable=no writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=yes entry_phys=0x000c7d60 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

case_bad_emitted() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=ready sections=2 emitted=3 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
    valid_sections
}

case_entry_ready_missing_mapped_entry() {
    entry_ready_map
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime phase=entry-ready index=0 flags=0x00000006 executable=yes writable=no preload=yes virtual_addr=0x00010000 virtual_size=65536 virtual_end=0x00020000 raw_addr=0x00000000 raw_size=65536 contains_entry=yes start_phys_mapped=yes start_phys=0x000c0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section context=browser-runtime phase=entry-ready index=1 flags=0x00000003 executable=no writable=yes preload=yes virtual_addr=0x00020000 virtual_size=65536 virtual_end=0x00030000 raw_addr=0x00010000 raw_size=65536 contains_entry=no start_phys_mapped=yes start_phys=0x000d0000 entry_phys_mapped=no entry_phys=0x00000000 source=virtual-header'
}

case_bad_phase() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-section-map context=browser-runtime status=ready phase=weird sections=2 emitted=2 executable_sections=1 entry_section=0 entry=0x00017d60 section_headers_addr=0x00010400 headers_size=2932 header_bytes=2932 source=virtual-header'
    valid_sections
}

run_case valid 0 'result=pass' valid_contract
run_case loaded-unmapped-entry 0 'phase=loaded' valid_loaded_unmapped_contract
run_case entry-ready 0 'phase=entry-ready' valid_entry_ready_contract
run_case missing-map 1 'reason=missing-section-map-marker' case_missing_map
run_case invalid-map 1 'reason=section-map-not-ready' case_invalid_map
run_case bad-context 1 'reason=missing-section-map-marker' case_bad_context
run_case missing-entry-row 1 'reason=missing-entry-section-row' case_missing_entry_row
run_case missing-executable-row 1 'reason=missing-executable-section-row' case_missing_executable_row
run_case bad-emitted 1 'reason=emitted-exceeds-sections' case_bad_emitted
run_case entry-ready-missing-mapped-entry 1 'reason=missing-mapped-entry-section-row' case_entry_ready_missing_mapped_entry
run_case bad-phase 1 'reason=bad-section-map-phase' case_bad_phase

printf 'DASHBOARD_SECTION_MAP_EVIDENCE_SELFTEST result=pass cases=11\n'
