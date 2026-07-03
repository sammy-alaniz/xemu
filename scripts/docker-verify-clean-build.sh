#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

usage() {
    cat <<EOF
Usage: $0 --yes

Runs a destructive clean-build verification:
  1. Refuses to run if tracked or untracked non-ignored files are present.
  2. Runs git clean -fdx to remove ignored build output.
  3. Builds all supported targets through Docker containers.

Commit or stash your work before using this script.
EOF
}

if [ "${1:-}" != "--yes" ]; then
    usage >&2
    exit 2
fi

cd "${repo_root}"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Refusing to run: tracked files have uncommitted changes." >&2
    git status --short >&2
    exit 1
fi

untracked="$(git ls-files --others --exclude-standard)"
if [ -n "${untracked}" ]; then
    echo "Refusing to run: untracked non-ignored files would be removed or obscure verification." >&2
    printf "%s\n" "${untracked}" >&2
    exit 1
fi

git clean -fdx
"${repo_root}/scripts/docker-build.sh" all
