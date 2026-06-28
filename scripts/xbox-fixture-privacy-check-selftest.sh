#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-fixture-privacy-check.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-fixture-privacy.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_repo() {
    local path="$1"

    mkdir -p "${path}"
    git -C "${path}" init -q
    git -C "${path}" config user.email xemu-fixture-privacy@example.invalid
    git -C "${path}" config user.name "xemu fixture privacy"
}

run_case() {
    local name="$1"
    local expected_status="$2"
    local expected_pattern="$3"
    local repo_path="${tmp_dir}/${name}"
    local out_path="${tmp_dir}/${name}.out"
    shift 3

    make_repo "${repo_path}"
    "$@" "${repo_path}"

    if "${script}" "${repo_path}" >"${out_path}" 2>&1; then
        status=0
    else
        status="$?"
    fi

    if [ "${status}" != "${expected_status}" ]; then
        printf 'FIXTURE_PRIVACY_SELFTEST case=%s result=fail reason=bad-status expected=%s actual=%s\n' \
            "${name}" "${expected_status}" "${status}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    if ! grep -q "${expected_pattern}" "${out_path}"; then
        printf 'FIXTURE_PRIVACY_SELFTEST case=%s result=fail reason=missing-pattern pattern=%s\n' \
            "${name}" "${expected_pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi

    cat "${out_path}"
    printf 'FIXTURE_PRIVACY_SELFTEST case=%s result=pass status=%s\n' "${name}" "${status}"
}

case_ignored() {
    local repo="$1"

    cat >"${repo}/.gitignore" <<'EOF'
/fixtures/
/xemu-fixtures/
EOF
    git -C "${repo}" add .gitignore
    git -C "${repo}" commit -q -m ignore-fixtures
}

case_ignored_present() {
    local repo="$1"

    mkdir -p "${repo}/fixtures"
    printf 'private-placeholder' >"${repo}/fixtures/flash.bin"
    cat >"${repo}/.gitignore" <<'EOF'
/fixtures/
/xemu-fixtures/
EOF
    git -C "${repo}" add .gitignore
    git -C "${repo}" commit -q -m ignore-fixtures
}

case_missing_ignore() {
    local repo="$1"

    cat >"${repo}/.gitignore" <<'EOF'
/build/
EOF
    git -C "${repo}" add .gitignore
    git -C "${repo}" commit -q -m missing-fixture-ignore
}

case_tracked_fixture() {
    local repo="$1"

    mkdir -p "${repo}/fixtures"
    printf 'private-placeholder' >"${repo}/fixtures/flash.bin"
    git -C "${repo}" add -f fixtures/flash.bin
    git -C "${repo}" commit -q -m tracked-fixture
    cat >"${repo}/.gitignore" <<'EOF'
/fixtures/
/xemu-fixtures/
EOF
    git -C "${repo}" add .gitignore
    git -C "${repo}" commit -q -m ignore-fixtures
}

run_case ignored 0 'item=file status=missing .*fixtures/flash.bin' case_ignored
run_case ignored-present 0 'item=file status=untracked .*fixtures/flash.bin' case_ignored_present
run_case missing-ignore 1 'status=not-ignored' case_missing_ignore
run_case tracked-fixture 1 'status=tracked' case_tracked_fixture

printf 'FIXTURE_PRIVACY_SELFTEST_RESULT result=pass cases=4\n'
