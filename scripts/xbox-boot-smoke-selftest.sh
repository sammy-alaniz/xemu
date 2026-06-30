#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-smoke-selftest.sh

Runs no-private-assets parser tests for xbox-boot-smoke.sh. The tests use a
fake native binary that emits controlled BOOT_MARK and BOOT_SMOKE_RESULT lines,
so they validate boot-level extraction, B3 HDD-read enforcement, metrics, and
failure reasons without starting xemu.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-boot-smoke.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-boot-smoke-selftest.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

flash_path="${tmp_dir}/flash.bin"
hdd_path="${tmp_dir}/xbox_hdd.img"
fake_binary="${tmp_dir}/fake-qemu-system-i386"

dd if=/dev/zero of="${flash_path}" bs=1024 count=1024 status=none
dd if=/dev/zero of="${hdd_path}" bs=1024 count=1024 status=none

cat >"${fake_binary}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

case "${XEMU_FAKE_SMOKE_CASE:-b2-pass}" in
    b2-pass)
        printf 'BOOT_MARK b0 machine=xbox cpu=initialized\n'
        printf 'BOOT_MARK b1 bios=loaded name=/tmp/flash.bin size=1048576\n'
        printf 'BOOT_MARK b2 device=ide initialized\n'
        printf 'BOOT_SMOKE_RESULT reason=timeout elapsed_ms=1000 exit=0\n'
        ;;
    b3-no-hdd-read)
        printf 'BOOT_MARK b0 machine=xbox cpu=initialized\n'
        printf 'BOOT_MARK b1 bios=loaded name=/tmp/flash.bin size=1048576\n'
        printf 'BOOT_MARK b2 device=ide initialized\n'
        printf 'BOOT_MARK b3 ide=hdd status=present\n'
        printf 'BOOT_SMOKE_RESULT reason=timeout elapsed_ms=1000 exit=0\n'
        ;;
    b3-pass)
        printf 'BOOT_MARK b0 machine=xbox cpu=initialized\n'
        printf 'BOOT_MARK b1 bios=loaded name=/tmp/flash.bin size=1048576\n'
        printf 'BOOT_MARK b2 device=ide initialized\n'
        printf 'BOOT_MARK b3 ide=hdd first_read_lba=0 nsectors=1 method=pio unit=0 total_sectors=2048\n'
        printf 'BOOT_SMOKE_RESULT reason=timeout elapsed_ms=1000 exit=0\n'
        ;;
    missing-result)
        printf 'BOOT_MARK b0 machine=xbox cpu=initialized\n'
        printf 'BOOT_MARK b1 bios=loaded name=/tmp/flash.bin size=1048576\n'
        printf 'BOOT_MARK b2 device=ide initialized\n'
        ;;
    below-expected)
        printf 'BOOT_MARK b0 machine=xbox cpu=initialized\n'
        printf 'BOOT_MARK b1 bios=loaded name=/tmp/flash.bin size=1048576\n'
        printf 'BOOT_SMOKE_RESULT reason=timeout elapsed_ms=1000 exit=0\n'
        ;;
    *)
        printf 'unknown fake smoke case: %s\n' "${XEMU_FAKE_SMOKE_CASE:-}" >&2
        exit 2
        ;;
esac
EOF
chmod +x "${fake_binary}"

run_case() {
    local name="$1"
    local fake_case="$2"
    local expect_level="$3"
    local expected_status="$4"
    local expected_pattern="$5"
    local out_dir="${tmp_dir}/${name}"
    local out_path="${tmp_dir}/${name}.out"

    mkdir -p "${out_dir}"
    if XEMU_FAKE_SMOKE_CASE="${fake_case}" \
        XEMU_SMOKE_BINARY="${fake_binary}" \
        XEMU_FLASH="${flash_path}" \
        XEMU_HDD="${hdd_path}" \
        XEMU_SMOKE_EXPECT_LEVEL="${expect_level}" \
        XEMU_SMOKE_OUT_DIR="${out_dir}" \
            "${script}" native-headless >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'BOOT_SMOKE_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'BOOT_SMOKE_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if [ ! -f "${out_dir}/boot-smoke.log" ]; then
        printf 'BOOT_SMOKE_SELFTEST case=%s result=fail reason=missing-log\n' "${name}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'BOOT_SMOKE_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

run_skip_boot_anim_config_case() {
    local name="skip-boot-anim-config"
    local out_dir="${tmp_dir}/${name}"
    local out_path="${tmp_dir}/${name}.out"

    mkdir -p "${out_dir}"
    XEMU_FAKE_SMOKE_CASE="b2-pass" \
    XEMU_SMOKE_BINARY="${fake_binary}" \
    XEMU_FLASH="${flash_path}" \
    XEMU_HDD="${hdd_path}" \
    XEMU_SMOKE_EXPECT_LEVEL="B2" \
    XEMU_SMOKE_OUT_DIR="${out_dir}" \
    XEMU_SMOKE_SKIP_BOOT_ANIM=1 \
        "${script}" native-headless >"${out_path}" 2>&1

    if ! grep -q '^skip_boot_anim = true$' "${out_dir}/xemu-smoke.toml"; then
        printf 'BOOT_SMOKE_SELFTEST case=%s result=fail reason=missing-skip-boot-anim-config\n' \
            "${name}" >&2
        cat "${out_dir}/xemu-smoke.toml" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'BOOT_SMOKE_SELFTEST case=%s result=pass status=0\n' "${name}"
}

run_case b2-pass b2-pass B2 0 'BOOT_SMOKE_SUMMARY result=pass .*level=B2 .*expected=B2'
run_case b3-missing-hdd-read b3-no-hdd-read B3 1 'reason=missing-b3-hdd-read'
run_case b3-pass b3-pass B3 0 'BOOT_SMOKE_SUMMARY result=pass .*level=B3 .*expected=B3'
run_case missing-result missing-result B2 1 'reason=missing-smoke-result'
run_case below-expected below-expected B2 1 'reason=missing-expected-level'
run_skip_boot_anim_config_case

printf 'BOOT_SMOKE_SELFTEST_RESULT result=pass cases=6\n'
