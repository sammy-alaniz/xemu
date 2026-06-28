#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-boot-next-step.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-boot-next-step.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

make_dirs() {
    local root="$1"

    mkdir -p \
        "${root}/synthetic/synthetic-matrix/native" \
        "${root}/synthetic/synthetic-matrix/wasm" \
        "${root}/synthetic/synthetic-matrix/browser-block" \
        "${root}/real"
}

write_synthetic_pass() {
    local root="$1"

    cat >"${root}/synthetic/synthetic-verify.log" <<'EOF'
BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=/tmp/synthetic host=pass runtime=pass matrix=pass
REAL_FIXTURE_LAYOUT_SELFTEST_RESULT result=pass cases=3
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

write_real_ready() {
    local root="$1"
    local dir="${2:-synthetic}"

    cat >"${root}/${dir}/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=0
EOF
}

write_real_b3() {
    local root="$1"

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
EOF
}

write_real_b3_fail() {
    local root="$1"

    cat >"${root}/real/real-b3-matrix.log" <<'EOF'
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass out_dir=/tmp/real
BOOT_REAL_B3_MATRIX_RESULT result=fail reason=browser-runtime log=/tmp/real/browser-runtime.log
REAL_B3_EVIDENCE result=fail reason=browser-runtime-evidence log=/tmp/real/real-b3-matrix.log
EOF
}

write_real_b4() {
    local root="$1"

    cat >>"${root}/real/real-b3-matrix.log" <<'EOF'
BOOT_MARK b4 display=visible
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=0123456789abcdef0123456789abcdef source=browser-canvas
EOF
}

run_case() {
    local name="$1"
    local pattern="$2"
    local root="${tmp_dir}/${name}"
    local out_path="${tmp_dir}/${name}.out"
    shift 2

    make_dirs "${root}"
    "$@" "${root}"

    if [ -f "${root}/next-step.env" ]; then
        (
            set -a
            . "${root}/next-step.env"
            set +a
            export XEMU_BOOT_NEXT_IGNORE_REPO_FIXTURES=1
            "${script}" "${root}/synthetic" "${root}/real"
        ) >"${out_path}"
    else
        XEMU_BOOT_NEXT_IGNORE_REPO_FIXTURES=1 \
            "${script}" "${root}/synthetic" "${root}/real" >"${out_path}"
    fi
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'XBOX_BOOT_NEXT_SELFTEST case=%s result=fail pattern=%s\n' "${name}" "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
    cat "${out_path}"
    printf 'XBOX_BOOT_NEXT_SELFTEST case=%s result=pass\n' "${name}"
}

case_synthetic_missing() {
    :
}

case_missing_fixtures() {
    cat >"${1}/synthetic/synthetic-verify.log" <<'EOF'
BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=/tmp/synthetic host=pass runtime=pass matrix=pass
BROWSER_HOST_CHECK result=pass base_url=http://127.0.0.1:1
BROWSER_RUNTIME_SMOKE result=pass mode=synthetic boot_result=timeout
EOF
    cat >"${1}/synthetic/synthetic-matrix/native/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF
    cat >"${1}/synthetic/synthetic-matrix/wasm/boot-smoke.log" <<'EOF'
BOOT_MARK b0 machine=xbox cpu=initialized
BOOT_MARK b1 bios=loaded
BOOT_MARK b2 device=ide initialized
EOF
    cat >"${1}/synthetic/synthetic-matrix/compare.log" <<'EOF'
BOOT_MARK_COMPARE result=pass mode=set baseline=B2 candidate=B2 expected=B2
EOF
    cat >"${1}/synthetic/synthetic-matrix/browser-block/browser-block-callback-smoke.log" <<'EOF'
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
EOF
}

case_missing_fixtures_after_layout() {
    write_synthetic_pass "$1"
    mkdir -p "${1}/layout-fixtures"
    printf 'XEMU_REAL_B3_FIXTURE_DIR=%s\n' "${1}/layout-fixtures" >"${1}/next-step.env"
}

case_ready_for_real_b3() {
    write_synthetic_pass "$1"
    write_real_ready "$1"
}

case_ready_for_real_b3_from_real_dir() {
    write_synthetic_pass "$1"
    write_real_ready "$1" real
}

case_b4_next() {
    write_synthetic_pass "$1"
    write_real_ready "$1"
    write_real_b3 "$1"
}

case_real_b3_failed() {
    write_synthetic_pass "$1"
    write_real_ready "$1" real
    write_real_b3_fail "$1"
}

case_real_preflight_fixtures_failed() {
    write_synthetic_pass "$1"
    cat >"${1}/real/real-fixture-ready.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=empty path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures require=1
EOF
    cat >"${1}/real/real-b3-matrix.log" <<'EOF'
REAL_FIXTURE_READY item=flash status=empty path=/tmp/fixtures/flash.bin
REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures require=1
BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures log=/tmp/real/real-fixture-ready.log
EOF
}

case_complete() {
    write_synthetic_pass "$1"
    write_real_ready "$1"
    write_real_b3 "$1"
    write_real_b4 "$1"
}

run_case synthetic-missing 'reason=synthetic-gate command_id=synthetic-gate command_json="scripts/xbox-browser-boot-verify-synthetic.sh"' case_synthetic_missing
run_case missing-fixtures 'reason=create-real-fixture-layout command_id=real-fixture-layout command_json="scripts/xbox-real-fixture-layout.sh --create"' case_missing_fixtures
run_case missing-fixtures-after-layout 'reason=add-real-fixtures command_id=real-fixtures-ready command_json="scripts/xbox-real-fixtures-ready.sh"' case_missing_fixtures_after_layout
run_case ready-real-b3 'reason=real-b3-preflight-and-matrix command_id=real-b3-matrix command_json="XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh && scripts/xbox-real-b3-matrix.sh"' case_ready_for_real_b3
run_case ready-real-b3-from-real-dir 'reason=real-b3-preflight-and-matrix command_id=real-b3-matrix command_json="XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh && scripts/xbox-real-b3-matrix.sh"' case_ready_for_real_b3_from_real_dir
run_case real-preflight-fixtures-failed 'reason=fix-real-fixtures command_id=real-fixtures-ready command_json="scripts/xbox-real-fixtures-ready.sh"' case_real_preflight_fixtures_failed
run_case real-b3-failed 'reason=real-b3-evidence-failed command_id=real-b3-evidence command_json="scripts/xbox-real-b3-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log"' case_real_b3_failed
run_case b4-next 'next=b4-visible-display .*command_id=b4-display-evidence command_json="scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log"' case_b4_next
run_case complete 'XBOX_BOOT_NEXT result=done next=done reason=complete command_id=audit-complete' case_complete

printf 'XBOX_BOOT_NEXT_SELFTEST_RESULT result=pass cases=9\n'
