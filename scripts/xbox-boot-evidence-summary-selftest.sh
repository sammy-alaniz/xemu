#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-evidence-summary-selftest.sh

Runs no-private-assets tests for xbox-boot-evidence-summary.sh. The tests build
temporary synthetic/real evidence directories and verify incomplete, B3-only,
B3+B4+B5, and complete B3+B4+B5+B6 summary behavior including strict exit
modes.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-evidence-summary-selftest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

synthetic_dir="${tmp_dir}/synthetic"
real_dir="${tmp_dir}/real"
mkdir -p \
    "${synthetic_dir}/synthetic-matrix/native" \
    "${synthetic_dir}/synthetic-matrix/wasm" \
    "${synthetic_dir}/synthetic-matrix/browser-block" \
    "${real_dir}"

cat >"${synthetic_dir}/synthetic-verify.log" <<'EOF'
BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=/tmp/synthetic host=pass runtime=pass matrix=pass
DOCKER_BUILD_CHECK result=pass native_dockerfile=/tmp/docker/xemu-native-build.Dockerfile wasm_dockerfile=/tmp/docker/xemu-wasm-build.Dockerfile scripts=3
REAL_FIXTURE_LAYOUT_SELFTEST_RESULT result=pass cases=3
BROWSER_HOST_CHECK result=pass base_url=http://127.0.0.1:1
BROWSER_RUNTIME_SMOKE result=pass mode=synthetic boot_result=timeout
EOF

cat >"${synthetic_dir}/synthetic-matrix/native/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF

cat >"${synthetic_dir}/synthetic-matrix/wasm/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF

cat >"${synthetic_dir}/synthetic-matrix/compare.log" <<'EOF'
BOOT_MARK_COMPARE result=pass mode=set baseline=B2 candidate=B2 expected=B2
EOF

cat >"${synthetic_dir}/synthetic-matrix/browser-block/browser-block-callback-smoke.log" <<'EOF'
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
EOF

run_summary() {
    "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"
}

expect_summary() {
    local name="$1"
    local pattern="$2"
    local log_path="${tmp_dir}/${name}.log"

    run_summary >"${log_path}"
    if ! grep -q "${pattern}" "${log_path}"; then
        printf 'EVIDENCE_SUMMARY_SELFTEST result=fail case=%s reason=missing-pattern pattern=%s\n' \
            "${name}" "${pattern}" >&2
        cat "${log_path}" >&2
        exit 1
    fi
    printf 'EVIDENCE_SUMMARY_SELFTEST case=%s result=pass\n' "${name}"
}

expect_strict_failure() {
    local name="$1"
    shift

    if "$@" >"${tmp_dir}/${name}.log" 2>&1; then
        printf 'EVIDENCE_SUMMARY_SELFTEST result=fail case=%s reason=unexpected-pass\n' "${name}" >&2
        cat "${tmp_dir}/${name}.log" >&2
        exit 1
    fi
    printf 'EVIDENCE_SUMMARY_SELFTEST case=%s result=pass\n' "${name}"
}

expect_strict_pass() {
    local name="$1"
    shift

    if ! "$@" >"${tmp_dir}/${name}.log" 2>&1; then
        printf 'EVIDENCE_SUMMARY_SELFTEST result=fail case=%s reason=unexpected-failure\n' "${name}" >&2
        cat "${tmp_dir}/${name}.log" >&2
        exit 1
    fi
    printf 'EVIDENCE_SUMMARY_SELFTEST case=%s result=pass\n' "${name}"
}

expect_summary missing-real 'BOOT_EVIDENCE_SUMMARY result=incomplete .*real_b3=missing .*next=real-b3-assets'
expect_summary docker-scaffold 'BOOT_EVIDENCE item=docker_build_scaffold status=pass'
expect_summary fixture-layout 'BOOT_EVIDENCE item=real_fixture_layout status=pass'
cat >>"${synthetic_dir}/synthetic-verify.log" <<EOF
REAL_FIXTURE_MANIFEST_RESULT result=pass next=real-b3-preflight output=/tmp/selftest/real-fixture-manifest.md readiness_log=/tmp/selftest/real-fixture-ready.log privacy_log=/tmp/selftest/fixture-privacy.log require=0
REAL_FIXTURE_MANIFEST_RESULT result=missing-required next=add-fixtures output=${synthetic_dir}/real-fixture-manifest/real-fixture-manifest.md readiness_log=${synthetic_dir}/real-fixture-manifest/real-fixture-ready.log privacy_log=${synthetic_dir}/real-fixture-manifest/fixture-privacy.log require=0
EOF
expect_summary fixture-manifest-live-result 'BOOT_EVIDENCE item=real_fixture_manifest status=missing-required'
expect_strict_failure require-real-b3-missing \
    env XEMU_EVIDENCE_REQUIRE_REAL_B3=1 \
        "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"

cat >"${real_dir}/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=0
EOF

expect_summary real-readiness-from-real-dir 'BOOT_EVIDENCE item=real_fixture_ready status=pass log=.*/real/real-fixture-ready.log'
mkdir -p "${real_dir}/real-fixture-manifest"
cat >"${real_dir}/real-fixture-manifest.log" <<EOF
REAL_FIXTURE_MANIFEST_RESULT result=pass next=real-b3-preflight output=${real_dir}/real-fixture-manifest/real-fixture-manifest.md readiness_log=${real_dir}/real-fixture-manifest/real-fixture-ready.log privacy_log=${real_dir}/real-fixture-manifest/fixture-privacy.log require=0
EOF
expect_summary real-manifest-from-real-dir 'BOOT_EVIDENCE item=real_fixture_manifest status=pass log=.*/real/real-fixture-manifest.log'

cat >"${real_dir}/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=missing path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures require=1
EOF
cat >"${real_dir}/real-b3-matrix.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=missing path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures require=1
BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures log=/tmp/real/real-fixture-ready.log
EOF

expect_summary real-preflight-missing-required 'BOOT_EVIDENCE item=real_fixture_preflight status=missing-required'
expect_summary real-b3-missing-fixtures 'BOOT_EVIDENCE_SUMMARY result=incomplete .*real_b3=missing .*next=real-b3-assets'

cat >"${real_dir}/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=empty path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures require=1
EOF
cat >"${real_dir}/real-b3-matrix.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=empty path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures require=1
BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures log=/tmp/real/real-fixture-ready.log
EOF

expect_summary real-preflight-fail 'BOOT_EVIDENCE item=real_fixture_preflight status=fail'

cat >"${real_dir}/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=0
EOF

cat >"${real_dir}/real-b3-matrix.log" <<'EOF'
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=/tmp/real
BOOT_REAL_B3_MATRIX_RESULT result=fail reason=browser-runtime log=/tmp/real/browser-runtime.log
REAL_B3_EVIDENCE result=fail reason=browser-runtime-evidence log=/tmp/real/real-b3-matrix.log
EOF

expect_summary real-b3-fail 'BOOT_EVIDENCE_SUMMARY result=incomplete .*real_b3=fail .*next=real-b3-assets'

cat >"${real_dir}/real-b3-matrix.log" <<'EOF'
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=/tmp/real
BOOT_MARK_COMPARE result=pass mode=set baseline=B3 candidate=B3 expected=B3
BOOT_MATRIX_RESULT result=pass expected=B3 compare=B3 out_dir=/tmp/real
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real open=yes read=yes hdd_bytes=1024 log=/tmp/real/browser-block.log
BROWSER_BLOCK_READ result=pass id=1 asset=hdd backend=node-file offset=0 bytes=512
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real lines=42 run_mode=selected-assets hdd_asset=yes b3_marker=browser-block capability_sab=yes artifact_js=yes artifact_wasm=yes asset_validate=yes config_persist=yes
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:1/browser/xbox-boot/" capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes b3=required boot_result=timeout
BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass out_dir=/tmp/real
EOF

expect_summary real-b3-only 'BOOT_EVIDENCE_SUMMARY result=incomplete .*real_b3=pass .*real_b4=missing .*real_b5=pass .*next=b4-visible-display'
expect_strict_pass require-real-b3-pass \
    env XEMU_EVIDENCE_REQUIRE_REAL_B3=1 \
        "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"
expect_strict_failure require-complete-b3-only \
    env XEMU_EVIDENCE_REQUIRE_COMPLETE=1 \
        "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"

cat >>"${real_dir}/real-b3-matrix.log" <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef0123456789abcdef source=browser-canvas
EOF

expect_summary b6-next 'BOOT_EVIDENCE_SUMMARY result=incomplete .*real_b3=pass .*real_b4=pass .*real_b5=pass .*real_b6=fail .*next=b6-dashboard-loaded'
expect_strict_failure require-complete-b6-missing \
    env XEMU_EVIDENCE_REQUIRE_COMPLETE=1 \
        "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"

cat >"${real_dir}/browser-runtime-firefox-bidi-browser-irq-pmc-limits-combined.log" <<'EOF'
BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=xboxdash.xbe path=xboxdash.xbe partition_lba=0 start_lba=1 sectors=1 file_size=512 first_cluster=2 cluster=2 read_index=1 read_lba=1 read_nsectors=1 overlap_lba=1 overlap_sectors=1 method=dma source=ide-read-log
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=4096 headers_size=512 entry=0x00010100 title_id=0xffff0002 source=virtual-header phys_addr=0x000e0000
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00010100 image_pc=0x00010100 entry_offset=0x00000100 image_base=0x00010000 image_size=4096 relation=overlap distance=0 address_mode=direct entry_phys_mapped=yes entry_phys=0x00020100 image_phys_mapped=yes image_phys=0x00020100 phys_match=yes entry_code_read=yes entry_code_hash=0x0123456789abcdef entry_opcode=0x55 source=virtual-header
BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x00010100 image_base=0x00010000 image_size=4096 phys_match=yes section_index=0 section_flags=0x00000006 section_virtual_addr=0x00010000 section_virtual_end=0x00011000 source=tcg-tb
NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=fedcba9876543210 width=640 height=480 dashboard=xbe-executed frame=1 build_id=synthetic
BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=0123456789abcdef native_hash=fedcba9876543210 source=browser-framebuffer width=640 height=480
EOF

expect_summary complete 'BOOT_EVIDENCE_SUMMARY result=complete .*real_b3=pass .*real_b4=pass .*real_b5=pass .*real_b6=pass .*next=done'
expect_strict_pass require-complete-pass \
    env XEMU_EVIDENCE_REQUIRE_COMPLETE=1 \
        "${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}"

printf 'EVIDENCE_SUMMARY_SELFTEST_RESULT result=pass cases=18\n'
