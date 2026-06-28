#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-evidence-summary.sh [synthetic-out-dir] [real-b3-out-dir]

Summarizes current Xbox browser boot evidence from smoke output directories.
The summary distinguishes synthetic harness evidence from real-asset evidence
so synthetic browser-block reads are not mistaken for real B3 boot proof.

Defaults:
  synthetic-out-dir: build-browser-boot-verify-synthetic
  real-b3-out-dir:   build-real-b3-matrix

Controls:
  XEMU_EVIDENCE_REQUIRE_REAL_B3  Exit nonzero if real B3 is missing when set to 1.
  XEMU_EVIDENCE_REQUIRE_COMPLETE Exit nonzero unless real B3, B4, and B5 pass.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
synthetic_dir="${1:-${repo_root}/build-browser-boot-verify-synthetic}"
real_dir="${2:-${repo_root}/build-real-b3-matrix}"

case "${synthetic_dir}" in
    /*) ;;
    *) synthetic_dir="${repo_root}/${synthetic_dir}" ;;
esac
case "${real_dir}" in
    /*) ;;
    *) real_dir="${repo_root}/${real_dir}" ;;
esac

synthetic_log="${synthetic_dir}/synthetic-verify.log"
synthetic_native_log="${synthetic_dir}/synthetic-matrix/native/boot-smoke.log"
synthetic_wasm_log="${synthetic_dir}/synthetic-matrix/wasm/boot-smoke.log"
synthetic_compare_log="${synthetic_dir}/synthetic-matrix/compare.log"
synthetic_browser_block_log="${synthetic_dir}/synthetic-matrix/browser-block/browser-block-callback-smoke.log"
synthetic_real_readiness_log="${synthetic_dir}/real-fixture-ready.log"
synthetic_real_manifest_log="${synthetic_dir}/real-fixture-manifest.log"
synthetic_real_manifest_output="${synthetic_dir}/real-fixture-manifest/real-fixture-manifest.md"
real_readiness_log="${real_dir}/real-fixture-ready.log"
real_manifest_log="${real_dir}/real-fixture-manifest.log"
real_manifest_output="${real_dir}/real-fixture-manifest/real-fixture-manifest.md"
real_log="${real_dir}/real-b3-matrix.log"

if [ ! -f "${real_readiness_log}" ]; then
    real_readiness_log="${synthetic_real_readiness_log}"
fi

if [ ! -f "${real_manifest_log}" ]; then
    real_manifest_log="${synthetic_log}"
    real_manifest_output="${synthetic_real_manifest_output}"
fi

has_line() {
    local file="$1"
    local pattern="$2"

    [ -f "${file}" ] && grep -q "${pattern}" "${file}"
}

count_level() {
    local file="$1"
    local level="$2"

    if [ ! -f "${file}" ]; then
        printf '0'
        return
    fi
    grep -c "^BOOT_MARK ${level}" "${file}" || true
}

highest_level() {
    local file="$1"
    local level
    local highest="none"

    for level in b0 b1 b2 b3 b4 b5; do
        if [ "$(count_level "${file}" "${level}")" -gt 0 ]; then
            highest="${level#b}"
        fi
    done

    printf '%s' "${highest}"
}

emit_status() {
    local item="$1"
    local status="$2"
    shift 2

    printf 'BOOT_EVIDENCE item=%s status=%s' "${item}" "${status}"
    if [ "$#" -gt 0 ]; then
        printf ' %s' "$*"
    fi
    printf '\n'
}

synthetic_gate="missing"
if has_line "${synthetic_log}" 'BROWSER_BOOT_SYNTHETIC_VERIFY result=pass .*host=pass runtime=pass matrix=pass'; then
    synthetic_gate="pass"
elif has_line "${synthetic_log}" 'VERIFY_STEP name=synthetic-matrix status=pass'; then
    synthetic_gate="pass"
fi
emit_status synthetic_gate "${synthetic_gate}" "log=${synthetic_log}"

if has_line "${synthetic_log}" '^DOCKER_BUILD_CHECK result=pass'; then
    emit_status docker_build_scaffold pass "log=${synthetic_log}"
else
    emit_status docker_build_scaffold missing "log=${synthetic_log}"
fi

if has_line "${synthetic_log}" '^REAL_FIXTURE_LAYOUT_SELFTEST_RESULT result=pass'; then
    emit_status real_fixture_layout pass "log=${synthetic_log}"
else
    emit_status real_fixture_layout missing "log=${synthetic_log}"
fi

if has_line "${real_manifest_log}" "^REAL_FIXTURE_MANIFEST_RESULT result=pass .*output=${real_manifest_output}"; then
    emit_status real_fixture_manifest pass "log=${real_manifest_log} output=${real_manifest_output}"
elif has_line "${real_manifest_log}" "^REAL_FIXTURE_MANIFEST_RESULT result=missing-required .*output=${real_manifest_output}"; then
    emit_status real_fixture_manifest missing-required "log=${real_manifest_log} output=${real_manifest_output}"
elif has_line "${real_manifest_log}" "^REAL_FIXTURE_MANIFEST_RESULT result=fail .*output=${real_manifest_output}"; then
    emit_status real_fixture_manifest fail "log=${real_manifest_log} output=${real_manifest_output}"
elif [ -f "${synthetic_real_manifest_log}" ]; then
    emit_status real_fixture_manifest missing "log=${synthetic_real_manifest_log} output=${synthetic_real_manifest_output}"
else
    emit_status real_fixture_manifest missing "log=${real_manifest_log} output=${real_manifest_output}"
fi

native_highest="$(highest_level "${synthetic_native_log}")"
wasm_highest="$(highest_level "${synthetic_wasm_log}")"

if has_line "${synthetic_compare_log}" 'BOOT_MARK_COMPARE result=pass'; then
    compare_status="pass"
else
    compare_status="missing"
fi

for level in b0 b1 b2; do
    native_count="$(count_level "${synthetic_native_log}" "${level}")"
    wasm_count="$(count_level "${synthetic_wasm_log}" "${level}")"
    if [ "${native_count}" -gt 0 ] && [ "${wasm_count}" -gt 0 ]; then
        emit_status "${level}_synthetic_native_wasm" pass \
            "native_markers=${native_count} wasm_markers=${wasm_count}"
    else
        emit_status "${level}_synthetic_native_wasm" missing \
            "native_markers=${native_count} wasm_markers=${wasm_count}"
    fi
done

emit_status synthetic_marker_compare "${compare_status}" "log=${synthetic_compare_log}"

if has_line "${synthetic_browser_block_log}" 'BOOT_MARK b3 browser_block=read'; then
    emit_status b3_browser_block_bridge synthetic-only "log=${synthetic_browser_block_log}"
else
    emit_status b3_browser_block_bridge missing "log=${synthetic_browser_block_log}"
fi

if has_line "${synthetic_log}" 'BROWSER_HOST_CHECK result=pass'; then
    emit_status b5_host_prereq pass "source=synthetic-host-check"
else
    emit_status b5_host_prereq missing "source=synthetic-host-check"
fi

if has_line "${synthetic_log}" 'BROWSER_RUNTIME_SMOKE result=pass' &&
   has_line "${synthetic_log}" 'mode=synthetic'; then
    emit_status b5_runtime_prereq pass "source=synthetic-browser-runtime"
else
    emit_status b5_runtime_prereq missing "source=synthetic-browser-runtime"
fi

if has_line "${real_readiness_log}" 'REAL_FIXTURE_READY_RESULT result=pass'; then
    real_fixture_ready="pass"
elif has_line "${real_readiness_log}" 'REAL_FIXTURE_READY_RESULT result=missing-required'; then
    real_fixture_ready="missing-required"
elif has_line "${real_readiness_log}" 'REAL_FIXTURE_READY_RESULT result=fail'; then
    real_fixture_ready="fail"
else
    real_fixture_ready="missing"
fi
emit_status real_fixture_ready "${real_fixture_ready}" "log=${real_readiness_log}"

if "${repo_root}/scripts/xbox-real-b3-evidence-check.sh" "${real_log}" >/dev/null 2>&1; then
    real_b3_status="pass"
elif has_line "${real_log}" '^BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures' &&
     [ "${real_fixture_ready}" = "missing-required" ]; then
    real_b3_status="missing"
elif has_line "${real_log}" '^REAL_B3_EVIDENCE result=fail' ||
     has_line "${real_log}" '^BOOT_REAL_B3_MATRIX_RESULT result=fail'; then
    real_b3_status="fail"
else
    real_b3_status="missing"
fi
if has_line "${real_log}" 'BOOT_REAL_B3_PREFLIGHT_RESULT result=pass'; then
    real_preflight_status="pass"
elif has_line "${real_log}" 'BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures' &&
     [ "${real_fixture_ready}" = "missing-required" ]; then
    real_preflight_status="missing-required"
elif has_line "${real_log}" 'BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures' ||
     has_line "${real_log}" 'REAL_FIXTURE_READY_RESULT result=fail'; then
    real_preflight_status="fail"
else
    real_preflight_status="missing"
fi
emit_status real_fixture_preflight "${real_preflight_status}" "log=${real_log}"
emit_status b3_real_assets "${real_b3_status}" "log=${real_log}"

if "${repo_root}/scripts/xbox-display-capture-evidence-check.sh" "${real_log}" >/dev/null 2>&1; then
    real_b4_status="pass"
else
    real_b4_status="missing"
fi
emit_status b4_visible_display "${real_b4_status}" "log=${real_log}"

if "${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh" "${real_log}" >/dev/null 2>&1; then
    real_b5_status="pass"
else
    real_b5_status="missing"
fi
emit_status b5_real_browser "${real_b5_status}" "log=${real_log}"

final_result="incomplete"
if [ "${real_b3_status}" != "pass" ]; then
    next_step="real-b3-assets"
elif [ "${real_b4_status}" != "pass" ]; then
    next_step="b4-visible-display"
elif [ "${real_b5_status}" != "pass" ]; then
    next_step="b5-real-browser"
else
    final_result="complete"
    next_step="done"
fi

printf 'BOOT_EVIDENCE_SUMMARY result=%s synthetic_native=B%s synthetic_wasm=B%s real_b3=%s real_b4=%s real_b5=%s next=%s synthetic_dir=%s real_dir=%s\n' \
    "${final_result}" "${native_highest}" "${wasm_highest}" \
    "${real_b3_status}" "${real_b4_status}" "${real_b5_status}" \
    "${next_step}" "${synthetic_dir}" "${real_dir}"

if [ "${XEMU_EVIDENCE_REQUIRE_REAL_B3:-0}" = "1" ] && [ "${real_b3_status}" != "pass" ]; then
    exit 1
fi

if [ "${XEMU_EVIDENCE_REQUIRE_COMPLETE:-0}" = "1" ] && [ "${final_result}" != "complete" ]; then
    exit 1
fi
