#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-real-fixture-layout.sh [--create]

Reports the local, ignored fixture layout expected by the real Xbox B3 matrix.
With --create, creates the fixture directory and a README only. It never creates,
copies, downloads, or modifies proprietary Xbox assets.

Controls:
  XEMU_REAL_B3_FIXTURE_DIR  Fixture dir. Default: fixtures/
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

create=0
if [ "${1:-}" = "--create" ]; then
    create=1
elif [ -n "${1:-}" ]; then
    usage >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fixture_dir="${XEMU_REAL_B3_FIXTURE_DIR:-${repo_root}/fixtures}"

case "${fixture_dir}" in
    /*) ;;
    *) fixture_dir="${repo_root}/${fixture_dir}" ;;
esac

if [ "${create}" = "1" ]; then
    mkdir -p "${fixture_dir}"
    readme="${fixture_dir}/README.txt"
    if [ ! -f "${readme}" ]; then
        cat >"${readme}" <<'EOF'
Local Xbox boot fixtures for xemu browser-boot work.

Place legally obtained private assets here. Do not commit this directory.

Required for real B3:
  flash.bin
  xbox_hdd.img

Optional:
  mcpx.bin      exactly 512 bytes when present
  eeprom.bin    exactly 256 bytes when present
  dvd.iso

Validate with:
  scripts/xbox-real-fixtures-ready.sh
EOF
    fi
fi

if [ -d "${fixture_dir}" ]; then
    dir_exists="yes"
    dir_status="present"
else
    dir_exists="no"
    dir_status="missing"
fi

printf 'REAL_FIXTURE_LAYOUT item=dir path=%s create=%s exists=%s\n' \
    "${fixture_dir}" "${create}" "${dir_exists}"
printf 'REAL_FIXTURE_LAYOUT item=flash required=yes file=flash.bin env=XEMU_FLASH\n'
printf 'REAL_FIXTURE_LAYOUT item=hdd required=yes file=xbox_hdd.img env=XEMU_HDD\n'
printf 'REAL_FIXTURE_LAYOUT item=mcpx required=no file=mcpx.bin env=XEMU_MCPX expected_bytes=512\n'
printf 'REAL_FIXTURE_LAYOUT item=eeprom required=no file=eeprom.bin env=XEMU_EEPROM expected_bytes=256\n'
printf 'REAL_FIXTURE_LAYOUT item=dvd required=no file=dvd.iso env=XEMU_DVD\n'
printf 'REAL_FIXTURE_LAYOUT_RESULT result=pass status=%s next=scripts/xbox-real-fixtures-ready.sh\n' \
    "${dir_status}"
