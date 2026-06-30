#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-dashboard-loaded-evidence.XXXXXX")"
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
        printf 'DASHBOARD_LOADED_EVIDENCE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'DASHBOARD_LOADED_EVIDENCE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'DASHBOARD_LOADED_EVIDENCE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

valid_read() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=xboxdash.xbe start_lba=123 sectors=16 file_size=8192 read_lba=123 read_nsectors=16 overlap_lba=123 overlap_sectors=16 source=ide-read-log'
}

valid_read_complete() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read-complete context=browser-runtime observed_seq=1 start_lba=123 expected_sectors=2048 contiguous_bytes=1048576 image_size=1048576 guest_addr=0x00010000 status=xbeh-present phys_addr=0x000e0000 sig=0x48454258 guest_pc=0x80010100 pc_known=yes page_status=mapped-page source=ide-dma-read-complete'
}

valid_loaded() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x10000 image_size=1048576 source=virtual-header'
}

valid_entry_ready() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
}

valid_executed() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x10100 phys_match=yes section_index=3 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
}

valid_native_reference() {
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed frame=1 build_id=synthetic'
}

valid_capture() {
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480'
}

valid_contract() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_native_reference
    valid_capture
}

valid_contract_read_complete() {
    valid_read_complete
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_native_reference
    valid_capture
}

case_missing_xbe_read() {
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_missing_xbe_read_complete() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read-progress context=browser-runtime observed_seq=1 read_lba=123 nsectors=8 start_lba=123 expected_sectors=2048 contiguous_bytes=4096 image_size=1048576 complete=no guest_addr=0x00010000 status=xbeh-present phys_addr=0x000e0000 sig=0x48454258 guest_pc=0x80010100 pc_known=yes page_status=mapped-page source=ide-dma-read-progress'
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_bad_xbe_read_complete_status() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read-complete context=browser-runtime observed_seq=1 start_lba=123 expected_sectors=2048 contiguous_bytes=1048576 image_size=1048576 guest_addr=0x00010000 status=mapped-non-xbe phys_addr=0x000e0000 sig=0x48454258 guest_pc=0x80010100 pc_known=yes page_status=mapped-page source=ide-dma-read-complete'
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_incomplete_xbe_read_complete() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read-complete context=browser-runtime observed_seq=1 start_lba=123 expected_sectors=2048 contiguous_bytes=4096 image_size=1048576 guest_addr=0x00010000 status=xbeh-present phys_addr=0x000e0000 sig=0x48454258 guest_pc=0x80010100 pc_known=yes page_status=mapped-page source=ide-dma-read-complete'
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_missing_xbe_loaded() {
    valid_read
    valid_entry_ready
    valid_executed
    valid_capture
}

case_diagnostics_do_not_load() {
    valid_read
    cat <<'EOF'
BOOT_MARK b6 dashboard=xbe-dma-buffer read_lba=123 nsectors=8 sg_addr=0x000be000 image_base=0x00010000 image_size=1048576 headers_size=4096 entry=0x12345678 source=ide-dma-buffer
BOOT_MARK b6 dashboard=xbe-read-progress context=browser-runtime observed_seq=1 read_lba=123 nsectors=8 start_lba=123 expected_sectors=2048 contiguous_bytes=4096 image_size=1048576 complete=no guest_addr=0x00010000 status=mapped-non-xbe phys_addr=0x00010000 sig=0x00000000 guest_pc=0xfff00100 pc_known=yes page_status=mapped-page source=ide-dma-read-progress
BOOT_MARK b6 dashboard=xbe-read-complete context=browser-runtime observed_seq=1 start_lba=123 expected_sectors=2048 contiguous_bytes=1048576 image_size=1048576 guest_addr=0x00010000 status=mapped-non-xbe phys_addr=0x00010000 sig=0x00000000 guest_pc=0xfff00100 pc_known=yes page_status=mapped-page source=ide-dma-read-complete
BOOT_MARK b6 dashboard=xbe-virtual-probe context=browser-runtime status=mapped-non-xbe observed_seq=1 guest_addr=0x00010000 phys_addr=0x00010000 sig=0x00000000 image_size=1048576 headers_size=4096 entry=0x12345678 dma_addr=0x000be000 guest_pc=0xfff00100 pc_known=yes source=virtual-probe
EOF
    valid_entry_ready
    valid_executed
    valid_capture
}

case_missing_xbe_entry_ready() {
    valid_read
    valid_loaded
    valid_executed
    valid_capture
}

case_missing_xbe_executed() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-exec-probe context=browser-runtime observed_seq=1 guest_pc=0xfff00100 tb_size=12 image_base=0x00010000 image_end=0x00110000 image_size=1048576 relation=above distance=4293853440 source=tcg-tb'
    valid_capture
}

case_bad_xbe_read_context() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read context=native-headless file=xboxdash.xbe start_lba=123 sectors=16 file_size=8192 read_lba=123 read_nsectors=16 overlap_lba=123 overlap_sectors=16 source=ide-read-log'
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_bad_xbe_loaded_context() {
    valid_read
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-loaded context=native-headless guest_addr=0x10000 image_size=1048576 source=virtual-header'
    valid_entry_ready
    valid_executed
    valid_capture
}

case_bad_xbe_entry_ready_context() {
    valid_read
    valid_loaded
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
    valid_executed
    valid_capture
}

case_bad_xbe_executed_context() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=native-headless guest_pc=0x10100 phys_match=yes section_index=3 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
    valid_capture
}

case_bad_xbe_file() {
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=dashboard.bin start_lba=123 sectors=16 file_size=8192 read_lba=123 read_nsectors=16 overlap_lba=123 overlap_sectors=16 source=ide-read-log'
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_bad_guest_addr() {
    valid_read
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=missing image_size=1048576 source=virtual-header'
    valid_entry_ready
    valid_executed
    valid_capture
}

case_bad_xbe_loaded_source() {
    valid_read
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x10000 image_size=1048576 source=physical-scan'
    valid_entry_ready
    valid_executed
    valid_capture
}

case_entry_code_unreadable() {
    valid_read
    valid_loaded
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=no entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
    valid_executed
    valid_capture
}

case_entry_phys_mismatch() {
    valid_read
    valid_loaded
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00030100 phys_match=no entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
    valid_executed
    valid_capture
}

case_bad_guest_entry() {
    valid_read
    valid_loaded
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=missing image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
    valid_executed
    valid_capture
}

case_bad_entry_phys() {
    valid_read
    valid_loaded
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=1048576 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=missing image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header'
    valid_executed
    valid_capture
}

case_bad_guest_pc() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=missing phys_match=yes section_index=3 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
    valid_capture
}

case_executed_phys_mismatch() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x10100 phys_match=no section_index=3 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
    valid_capture
}

case_bad_section_flags() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x10100 phys_match=yes section_index=3 section_flags=missing section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
    valid_capture
}

case_section_not_executable() {
    valid_read
    valid_loaded
    valid_entry_ready
    printf '%s\n' 'BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x10100 phys_match=yes section_index=3 section_flags=0x00000002 section_virtual_addr=0x00010000 section_virtual_end=0x00020000'
    valid_capture
}

case_missing_capture() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
}

case_capture_not_pass() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=fail native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480'
}

case_native_ref_mismatch() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=no hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480'
}

case_bad_hash() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=not-a-hash native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480'
}

case_bad_native_hash() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=not-a-hash source=browser-framebuffer width=640 height=480'
}

case_bad_source() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=manual-note width=640 height=480'
}

case_bad_width() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=0 height=480'
}

case_bad_height() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=0'
}

case_missing_native_reference() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    valid_capture
}

case_native_reference_not_pass() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=fail context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
    valid_capture
}

case_bad_native_reference_context() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=browser-runtime source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
    valid_capture
}

case_bad_native_reference_source() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=browser-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed'
    valid_capture
}

case_bad_native_reference_hash() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=not-a-hash width=640 height=480 dashboard=xbe-executed'
    valid_capture
}

case_native_reference_hash_mismatch() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=aaaaaaaaaaaaaaaa width=640 height=480 dashboard=xbe-executed'
    valid_capture
}

case_native_reference_width_mismatch() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=800 height=480 dashboard=xbe-executed'
    valid_capture
}

case_native_reference_height_mismatch() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=600 dashboard=xbe-executed'
    valid_capture
}

case_bad_native_reference_dashboard() {
    valid_read
    valid_loaded
    valid_entry_ready
    valid_executed
    printf '%s\n' 'NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-loaded'
    valid_capture
}

case_pass() {
    valid_contract
}

run_case missing-xbe-read 1 'reason=missing-xbe-read-marker' case_missing_xbe_read
run_case missing-xbe-read-complete 1 'reason=missing-xbe-read-complete-marker' case_missing_xbe_read_complete
run_case missing-xbe-loaded 1 'reason=missing-xbe-loaded-marker' case_missing_xbe_loaded
run_case diagnostics-do-not-load 1 'reason=missing-xbe-loaded-marker' case_diagnostics_do_not_load
run_case missing-xbe-entry-ready 1 'reason=missing-xbe-entry-ready-marker' case_missing_xbe_entry_ready
run_case missing-xbe-executed 1 'reason=missing-xbe-executed-marker' case_missing_xbe_executed
run_case bad-xbe-read-context 1 'reason=bad-xbe-read-context' case_bad_xbe_read_context
run_case bad-xbe-read-complete-status 1 'reason=bad-xbe-read-status' case_bad_xbe_read_complete_status
run_case incomplete-xbe-read-complete 1 'reason=incomplete-xbe-read' case_incomplete_xbe_read_complete
run_case bad-xbe-loaded-context 1 'reason=bad-xbe-loaded-context' case_bad_xbe_loaded_context
run_case bad-xbe-entry-ready-context 1 'reason=bad-xbe-entry-ready-context' case_bad_xbe_entry_ready_context
run_case bad-xbe-executed-context 1 'reason=bad-xbe-executed-context' case_bad_xbe_executed_context
run_case bad-xbe-file 1 'reason=bad-xbe-file' case_bad_xbe_file
run_case bad-guest-addr 1 'reason=bad-guest-addr' case_bad_guest_addr
run_case bad-xbe-loaded-source 1 'reason=bad-xbe-loaded-source' case_bad_xbe_loaded_source
run_case entry-code-unreadable 1 'reason=entry-code-unreadable' case_entry_code_unreadable
run_case entry-phys-mismatch 1 'reason=entry-phys-mismatch' case_entry_phys_mismatch
run_case bad-guest-entry 1 'reason=bad-guest-entry' case_bad_guest_entry
run_case bad-entry-phys 1 'reason=bad-entry-phys' case_bad_entry_phys
run_case bad-guest-pc 1 'reason=bad-guest-pc' case_bad_guest_pc
run_case executed-phys-mismatch 1 'reason=executed-phys-mismatch' case_executed_phys_mismatch
run_case bad-section-flags 1 'reason=bad-section-flags' case_bad_section_flags
run_case section-not-executable 1 'reason=section-not-executable' case_section_not_executable
run_case missing-capture 1 'reason=missing-dashboard-capture' case_missing_capture
run_case capture-not-pass 1 'reason=capture-not-pass' case_capture_not_pass
run_case native-ref-mismatch 1 'reason=native-ref-mismatch' case_native_ref_mismatch
run_case bad-hash 1 'reason=bad-hash' case_bad_hash
run_case bad-native-hash 1 'reason=bad-native-hash' case_bad_native_hash
run_case bad-source 1 'reason=bad-source' case_bad_source
run_case bad-width 1 'reason=bad-width' case_bad_width
run_case bad-height 1 'reason=bad-height' case_bad_height
run_case missing-native-reference 1 'reason=missing-native-reference' case_missing_native_reference
run_case native-reference-not-pass 1 'reason=native-reference-not-pass' case_native_reference_not_pass
run_case bad-native-reference-context 1 'reason=bad-native-reference-context' case_bad_native_reference_context
run_case bad-native-reference-source 1 'reason=bad-native-reference-source' case_bad_native_reference_source
run_case bad-native-reference-hash 1 'reason=bad-native-reference-hash' case_bad_native_reference_hash
run_case native-reference-hash-mismatch 1 'reason=native-reference-hash-mismatch' case_native_reference_hash_mismatch
run_case native-reference-width-mismatch 1 'reason=native-reference-width-mismatch' case_native_reference_width_mismatch
run_case native-reference-height-mismatch 1 'reason=native-reference-height-mismatch' case_native_reference_height_mismatch
run_case bad-native-reference-dashboard 1 'reason=bad-native-reference-dashboard' case_bad_native_reference_dashboard
run_case pass 0 'DASHBOARD_LOADED_EVIDENCE result=pass' case_pass
run_case pass-read-complete 0 'DASHBOARD_LOADED_EVIDENCE result=pass' valid_contract_read_complete

printf 'DASHBOARD_LOADED_EVIDENCE_SELFTEST_RESULT result=pass cases=42\n'
