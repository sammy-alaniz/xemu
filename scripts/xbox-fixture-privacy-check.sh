#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-fixture-privacy-check.sh [repo-root]

Verifies that standard private Xbox fixture locations are ignored by git and
that known fixture filenames are not tracked. This script prints paths only;
it never reads fixture contents.

Standard ignored directories:
  fixtures/
  xemu-fixtures/

Known private fixture filenames:
  flash.bin
  xbox_hdd.img
  mcpx.bin
  eeprom.bin
  dvd.iso
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)}"
case "${repo_root}" in
    /*) ;;
    *) repo_root="$(cd "${repo_root}" >/dev/null 2>&1 && pwd)" ;;
esac

fixture_dirs=(fixtures xemu-fixtures)
fixture_files=(flash.bin xbox_hdd.img mcpx.bin eeprom.bin dvd.iso)
failed=0

git_in_repo() {
    git -C "${repo_root}" "$@"
}

if ! git_in_repo rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'FIXTURE_PRIVACY result=fail reason=not-git-repo repo=%s\n' "${repo_root}" >&2
    exit 2
fi

for dir in "${fixture_dirs[@]}"; do
    if git_in_repo check-ignore -q "${dir}/"; then
        printf 'FIXTURE_PRIVACY item=dir status=ignored path=%s/%s/\n' "${repo_root}" "${dir}"
    else
        printf 'FIXTURE_PRIVACY item=dir status=not-ignored path=%s/%s/\n' "${repo_root}" "${dir}" >&2
        failed=1
    fi
done

for dir in "${fixture_dirs[@]}"; do
    for file in "${fixture_files[@]}"; do
        rel_path="${dir}/${file}"
        if git_in_repo ls-files --error-unmatch "${rel_path}" >/dev/null 2>&1; then
            printf 'FIXTURE_PRIVACY item=file status=tracked path=%s/%s\n' "${repo_root}" "${rel_path}" >&2
            failed=1
        elif [ -e "${repo_root}/${rel_path}" ]; then
            printf 'FIXTURE_PRIVACY item=file status=untracked path=%s/%s\n' "${repo_root}" "${rel_path}"
        else
            printf 'FIXTURE_PRIVACY item=file status=missing path=%s/%s\n' "${repo_root}" "${rel_path}"
        fi
    done
done

if [ "${failed}" = "1" ]; then
    printf 'FIXTURE_PRIVACY_RESULT result=fail repo=%s\n' "${repo_root}" >&2
    exit 1
fi

printf 'FIXTURE_PRIVACY_RESULT result=pass repo=%s\n' "${repo_root}"
