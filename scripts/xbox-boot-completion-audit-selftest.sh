#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-boot-completion-audit.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-completion-audit.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_dirs() {
    local root="$1"

    mkdir -p \
        "${root}/synthetic/synthetic-matrix/native" \
        "${root}/synthetic/synthetic-matrix/wasm" \
        "${root}/synthetic/synthetic-matrix/browser-block" \
        "${root}/synthetic/real-fixture-manifest" \
        "${root}/real/real-fixture-manifest"
}

write_synthetic_pass() {
    local root="$1"

    cat >"${root}/synthetic/synthetic-verify.log" <<EOF
BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=${root}/synthetic host=pass runtime=pass matrix=pass
DOCKER_BUILD_CHECK result=pass native_dockerfile=/tmp/native.Dockerfile wasm_dockerfile=/tmp/wasm.Dockerfile scripts=3
REAL_FIXTURE_LAYOUT_SELFTEST_RESULT result=pass cases=3
REAL_FIXTURE_MANIFEST_RESULT result=missing-required next=add-fixtures output=${root}/synthetic/real-fixture-manifest/real-fixture-manifest.md readiness_log=${root}/synthetic/real-fixture-manifest/real-fixture-ready.log privacy_log=${root}/synthetic/real-fixture-manifest/fixture-privacy.log require=0
BROWSER_HOST_CHECK result=pass base_url=http://127.0.0.1:1
BROWSER_RUNTIME_SMOKE result=pass mode=synthetic boot_result=timeout
EOF
    cat >"${root}/synthetic/synthetic-matrix/native/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF
    cat >"${root}/synthetic/synthetic-matrix/wasm/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF
    cat >"${root}/synthetic/synthetic-matrix/compare.log" <<'EOF'
BOOT_MARK_COMPARE result=pass mode=set baseline=B2 candidate=B2 expected=B2
EOF
    cat >"${root}/synthetic/synthetic-matrix/browser-block/browser-block-callback-smoke.log" <<'EOF'
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
EOF
}

write_complete_real() {
    local root="$1"

    cat >"${root}/real/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=1
EOF
    cat >"${root}/real/real-fixture-manifest.log" <<EOF
REAL_FIXTURE_MANIFEST_RESULT result=pass next=real-b3-preflight output=${root}/real/real-fixture-manifest/real-fixture-manifest.md readiness_log=${root}/real/real-fixture-manifest/real-fixture-ready.log privacy_log=${root}/real/real-fixture-manifest/fixture-privacy.log require=0
EOF
    cat >"${root}/real/real-b3-matrix.log" <<'EOF'
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=/tmp/real
BOOT_MARK_COMPARE result=pass mode=set baseline=B3 candidate=B3 expected=B3
BOOT_MATRIX_RESULT result=pass expected=B3 compare=B3 out_dir=/tmp/real
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real open=yes read=yes hdd_bytes=1024 log=/tmp/real/browser-block.log
BROWSER_BLOCK_READ result=pass id=1 asset=hdd backend=node-file offset=0 bytes=512
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real lines=42 run_mode=selected-assets hdd_asset=yes b3_marker=browser-block capability_sab=yes artifact_js=yes artifact_wasm=yes asset_validate=yes config_persist=yes
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required boot_result=timeout
BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass out_dir=/tmp/real
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef0123456789abcdef source=browser-canvas
EOF
}

write_b6_pass() {
    local root="$1"

    cat >"${root}/real/browser-runtime-firefox-bidi-pgraph-notify-probe-90s-combined.log" <<'EOF'
BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=xboxdash.xbe path=xboxdash.xbe partition_lba=0 start_lba=1 sectors=1 file_size=512 first_cluster=2 cluster=2 read_index=1 read_lba=1 read_nsectors=1 overlap_lba=1 overlap_sectors=1 method=dma source=ide-read-log
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=4096 headers_size=512 entry=0x00010100 title_id=0xffff0002 source=virtual-header phys_addr=0x000e0000
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=4096 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header
BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x00010100 image_base=0x00010000 image_size=4096 phys_match=yes section_index=0 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00011000 source=tcg-tb
NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed frame=1 build_id=synthetic
BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480
EOF
}

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local root="${tmp_dir}/${name}"
    local log_path="${tmp_dir}/${name}.log"
    shift 3

    make_dirs "${root}"
    "$@" "${root}"

    if "${script}" "${root}/synthetic" "${root}/real" >"${log_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'BOOT_COMPLETION_AUDIT_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${log_path}"; then
        printf 'BOOT_COMPLETION_AUDIT_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${log_path}" >&2
        exit 1
    fi

    cat "${log_path}"
    printf 'BOOT_COMPLETION_AUDIT_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_incomplete() {
    write_synthetic_pass "$1"
    cat >"${1}/real/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures require=1
EOF
}

case_complete() {
    write_synthetic_pass "$1"
    write_complete_real "$1"
    write_b6_pass "$1"
}

case_b6_incomplete() {
    write_synthetic_pass "$1"
    write_complete_real "$1"
}

run_case incomplete 1 'BOOT_COMPLETION_AUDIT_RESULT result=fail' case_incomplete
run_case b6-incomplete 1 'BOOT_COMPLETION item=real_b6 result=fail' case_b6_incomplete
run_case complete 0 'BOOT_COMPLETION_AUDIT_RESULT result=pass failed=0 next=done' case_complete

printf 'BOOT_COMPLETION_AUDIT_SELFTEST_RESULT result=pass cases=3\n'
