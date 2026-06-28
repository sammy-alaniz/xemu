#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-b3-matrix-selftest.sh

Runs a no-private-assets self-test for xbox-real-b3-matrix.sh fixture
auto-discovery and fixture gating. The test creates synthetic files with the
documented fixture names, runs preflight-only mode, verifies the real B3 wrapper
reaches its explicit preflight-pass marker without starting emulator execution,
and verifies an empty required fixture stops the matrix before preflight.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-real-b3-selftest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

fixture_dir="${tmp_dir}/fixtures"
out_dir="${tmp_dir}/out"
full_out_dir="${tmp_dir}/full-out"
bad_fixture_dir="${tmp_dir}/bad-fixtures"
bad_out_dir="${tmp_dir}/bad-out"
mkdir -p "${fixture_dir}"

make_file() {
    local path="$1"
    local size="$2"

    dd if=/dev/zero of="${path}" bs=1 count=0 seek="${size}" status=none
}

make_file "${fixture_dir}/flash.bin" 1048576
make_file "${fixture_dir}/xbox_hdd.img" 16777216
make_file "${fixture_dir}/mcpx.bin" 512
make_file "${fixture_dir}/eeprom.bin" 256
make_file "${fixture_dir}/dvd.iso" 2048

log_path="${tmp_dir}/real-b3-selftest.log"
full_log_path="${tmp_dir}/real-b3-full-skip-selftest.log"
bad_log_path="${tmp_dir}/real-b3-bad-fixture.log"

if ! env -i PATH="${PATH}" \
    XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
    XEMU_REAL_B3_OUT_DIR="${out_dir}" \
    XEMU_REAL_B3_PREFLIGHT_ONLY=1 \
        "${repo_root}/scripts/xbox-real-b3-matrix.sh" >"${log_path}" 2>&1; then
    printf 'REAL_B3_SELFTEST result=fail reason=wrapper-failed log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

for name in XEMU_FLASH XEMU_HDD XEMU_MCPX XEMU_EEPROM XEMU_DVD; do
    if ! grep -q "BOOT_REAL_B3_AUTODETECT name=${name}" "${log_path}"; then
        printf 'REAL_B3_SELFTEST result=fail reason=missing-autodetect name=%s log=%s\n' \
            "${name}" "${log_path}" >&2
        cat "${log_path}" >&2
        exit 1
    fi
done

if ! grep -q 'BOOT_FIXTURE_RESULT result=pass' "${log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-fixture-pass log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_READY_RESULT result=pass' "${log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-readiness-pass log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_MANIFEST_RESULT result=pass' "${log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-manifest-pass log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_MANIFEST_RESULT result=pass' "${out_dir}/real-fixture-manifest.log" ||
   ! grep -q 'Result | pass' "${out_dir}/real-fixture-manifest/real-fixture-manifest.md"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-manifest-files log=%s\n' \
        "${out_dir}/real-fixture-manifest.log" >&2
    cat "${log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_READY_RESULT result=pass' "${out_dir}/real-fixture-ready.log"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-readiness-log log=%s\n' \
        "${out_dir}/real-fixture-ready.log" >&2
    cat "${log_path}" >&2
    exit 1
fi

if ! grep -q 'BOOT_REAL_B3_PREFLIGHT_RESULT result=pass' "${log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-preflight-pass log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

if grep -q '^REAL_B3_EVIDENCE ' "${log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=unexpected-evidence-check log=%s\n' "${log_path}" >&2
    cat "${log_path}" >&2
    exit 1
fi

if env -i PATH="${PATH}" \
    XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
    XEMU_REAL_B3_OUT_DIR="${full_out_dir}" \
    XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
    XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
    XEMU_REAL_B3_SKIP_BROWSER_RUNTIME=1 \
        "${repo_root}/scripts/xbox-real-b3-matrix.sh" >"${full_log_path}" 2>&1; then
    printf 'REAL_B3_SELFTEST result=fail reason=unexpected-full-skip-pass log=%s\n' \
        "${full_log_path}" >&2
    cat "${full_log_path}" >&2
    exit 1
fi

if ! grep -q 'BOOT_REAL_B3_PREFLIGHT_RESULT result=pass' "${full_log_path}" ||
   ! grep -q 'BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=skipped browser_block=skipped browser_runtime=skipped' "${full_log_path}" ||
   ! grep -q '^REAL_B3_EVIDENCE result=fail reason=missing-b3-matrix-pass' "${full_log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-full-skip-evidence log=%s\n' \
        "${full_log_path}" >&2
    cat "${full_log_path}" >&2
    exit 1
fi

mkdir -p "${bad_fixture_dir}"
make_file "${bad_fixture_dir}/flash.bin" 0
make_file "${bad_fixture_dir}/xbox_hdd.img" 16777216

if env -i PATH="${PATH}" \
    XEMU_REAL_B3_FIXTURE_DIR="${bad_fixture_dir}" \
    XEMU_REAL_B3_OUT_DIR="${bad_out_dir}" \
    XEMU_REAL_B3_PREFLIGHT_ONLY=1 \
        "${repo_root}/scripts/xbox-real-b3-matrix.sh" >"${bad_log_path}" 2>&1; then
    printf 'REAL_B3_SELFTEST result=fail reason=unexpected-bad-fixture-pass log=%s\n' "${bad_log_path}" >&2
    cat "${bad_log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_READY item=flash status=empty' "${bad_log_path}" ||
   ! grep -q 'REAL_FIXTURE_MANIFEST_RESULT result=fail next=fix-fixtures' "${bad_log_path}" ||
   ! grep -q 'REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures' "${bad_log_path}" ||
   ! grep -q 'BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures' "${bad_log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-bad-fixture-evidence log=%s\n' "${bad_log_path}" >&2
    cat "${bad_log_path}" >&2
    exit 1
fi

if grep -q 'BOOT_FIXTURE_RESULT result=pass' "${bad_log_path}" ||
   grep -q 'BOOT_REAL_B3_PREFLIGHT_RESULT result=pass' "${bad_log_path}" ||
   grep -q '^REAL_B3_EVIDENCE ' "${bad_log_path}"; then
    printf 'REAL_B3_SELFTEST result=fail reason=bad-fixture-advanced-too-far log=%s\n' "${bad_log_path}" >&2
    cat "${bad_log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures' "${bad_out_dir}/real-fixture-ready.log"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-bad-readiness-log log=%s\n' \
        "${bad_out_dir}/real-fixture-ready.log" >&2
    cat "${bad_log_path}" >&2
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_MANIFEST_RESULT result=fail next=fix-fixtures' "${bad_out_dir}/real-fixture-manifest.log"; then
    printf 'REAL_B3_SELFTEST result=fail reason=missing-bad-manifest-log log=%s\n' \
        "${bad_out_dir}/real-fixture-manifest.log" >&2
    cat "${bad_log_path}" >&2
    exit 1
fi

printf 'REAL_B3_SELFTEST result=pass autodetect=yes fixture_check=yes manifest=yes preflight_only=yes full_preflight_marker=yes bad_fixture_guard=yes\n'
