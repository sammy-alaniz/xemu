#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-fixture-layout-selftest.sh

Runs no-private-assets tests for xbox-real-fixture-layout.sh.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-real-fixture-layout.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

fixture_dir="${tmp_dir}/fixtures"
check_log="${tmp_dir}/check.log"
create_log="${tmp_dir}/create.log"
ready_log="${tmp_dir}/ready.log"

XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
    "${repo_root}/scripts/xbox-real-fixture-layout.sh" >"${check_log}"

if ! grep -q 'REAL_FIXTURE_LAYOUT item=dir .*exists=no' "${check_log}" ||
   ! grep -q 'REAL_FIXTURE_LAYOUT item=flash required=yes file=flash.bin env=XEMU_FLASH' "${check_log}" ||
   ! grep -q 'REAL_FIXTURE_LAYOUT_RESULT result=pass status=missing next=scripts/xbox-real-fixtures-ready.sh' "${check_log}"; then
    printf 'REAL_FIXTURE_LAYOUT_SELFTEST result=fail case=check reason=missing-layout-evidence log=%s\n' "${check_log}" >&2
    cat "${check_log}" >&2
    exit 1
fi
printf 'REAL_FIXTURE_LAYOUT_SELFTEST case=check result=pass\n'

XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
    "${repo_root}/scripts/xbox-real-fixture-layout.sh" --create >"${create_log}"

if [ ! -d "${fixture_dir}" ] ||
   [ ! -f "${fixture_dir}/README.txt" ] ||
   [ -e "${fixture_dir}/flash.bin" ] ||
   [ -e "${fixture_dir}/xbox_hdd.img" ]; then
    printf 'REAL_FIXTURE_LAYOUT_SELFTEST result=fail case=create reason=bad-created-files dir=%s\n' "${fixture_dir}" >&2
    ls -la "${fixture_dir}" >&2 || true
    exit 1
fi

if ! grep -q 'REAL_FIXTURE_LAYOUT item=dir .*create=1 exists=yes' "${create_log}" ||
   ! grep -q 'REAL_FIXTURE_LAYOUT_RESULT result=pass status=present next=scripts/xbox-real-fixtures-ready.sh' "${create_log}"; then
    printf 'REAL_FIXTURE_LAYOUT_SELFTEST result=fail case=create reason=missing-create-evidence log=%s\n' "${create_log}" >&2
    cat "${create_log}" >&2
    exit 1
fi
printf 'REAL_FIXTURE_LAYOUT_SELFTEST case=create result=pass\n'

XEMU_REAL_B3_FIXTURE_DIR="${fixture_dir}" \
    "${repo_root}/scripts/xbox-real-fixtures-ready.sh" >"${ready_log}"

if ! grep -q 'REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures' "${ready_log}"; then
    printf 'REAL_FIXTURE_LAYOUT_SELFTEST result=fail case=readiness reason=unexpected-readiness log=%s\n' "${ready_log}" >&2
    cat "${ready_log}" >&2
    exit 1
fi
printf 'REAL_FIXTURE_LAYOUT_SELFTEST case=readiness result=pass\n'

printf 'REAL_FIXTURE_LAYOUT_SELFTEST_RESULT result=pass cases=3\n'
