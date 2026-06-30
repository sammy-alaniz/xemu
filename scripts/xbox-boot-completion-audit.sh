#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-completion-audit.sh [synthetic-out-dir] [real-b3-out-dir]

Audits the Xbox browser boot evidence against the end-to-end completion
contract. This is stricter and more diagnostic than the summary command: it
prints one BOOT_COMPLETION item for every required gate and exits nonzero until
the real B3, B4, B5, and B6 evidence is complete.

Defaults:
  synthetic-out-dir: build-browser-boot-verify-synthetic
  real-b3-out-dir:   build-real-b3-matrix

Controls:
  XEMU_COMPLETION_AUDIT_ALLOW_INCOMPLETE  Exit 0 even when the audit fails.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
synthetic_dir="${1:-${repo_root}/build-browser-boot-verify-synthetic}"
real_dir="${2:-${repo_root}/build-real-b3-matrix}"
allow_incomplete="${XEMU_COMPLETION_AUDIT_ALLOW_INCOMPLETE:-0}"

case "${synthetic_dir}" in
    /*) ;;
    *) synthetic_dir="${repo_root}/${synthetic_dir}" ;;
esac
case "${real_dir}" in
    /*) ;;
    *) real_dir="${repo_root}/${real_dir}" ;;
esac

summary_path="$(mktemp "${TMPDIR:-/tmp}/xemu-completion-audit.XXXXXX")"
trap 'rm -f "${summary_path}"' EXIT

"${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}" >"${summary_path}"

value_for() {
    local line="$1"
    local key="$2"
    local token

    for token in ${line}; do
        case "${token}" in
            "${key}="*)
                printf '%s' "${token#*=}"
                return
                ;;
        esac
    done
}

status_for() {
    local item="$1"
    local line

    line="$(grep "^BOOT_EVIDENCE item=${item} " "${summary_path}" || true)"
    if [ -z "${line}" ]; then
        printf 'missing'
        return
    fi
    value_for "${line}" status
}

emit_gate() {
    local gate="$1"
    local actual="$2"
    local expected="$3"
    local detail="$4"
    local result="fail"

    if [ "${actual}" = "${expected}" ]; then
        result="pass"
    fi

    if [ "${result}" != "pass" ]; then
        failed=$((failed + 1))
    fi

    printf 'BOOT_COMPLETION item=%s result=%s expected=%s actual=%s detail=%s\n' \
        "${gate}" "${result}" "${expected}" "${actual}" "${detail}"
}

summary_line="$(grep '^BOOT_EVIDENCE_SUMMARY ' "${summary_path}")"
summary_result="$(value_for "${summary_line}" result)"
next_step="$(value_for "${summary_line}" next)"
synthetic_native="$(value_for "${summary_line}" synthetic_native)"
synthetic_wasm="$(value_for "${summary_line}" synthetic_wasm)"
real_b3="$(value_for "${summary_line}" real_b3)"
real_b4="$(value_for "${summary_line}" real_b4)"
real_b5="$(value_for "${summary_line}" real_b5)"
real_b6="$(value_for "${summary_line}" real_b6)"

failed=0

emit_gate synthetic_gate "$(status_for synthetic_gate)" pass no-private-assets-aggregate
emit_gate docker_build_scaffold "$(status_for docker_build_scaffold)" pass reduced-build-settings
emit_gate synthetic_b0 "$(status_for b0_synthetic_native_wasm)" pass native-and-wasm-machine-constructed
emit_gate synthetic_b1 "$(status_for b1_synthetic_native_wasm)" pass native-and-wasm-firmware-loaded
emit_gate synthetic_b2 "$(status_for b2_synthetic_native_wasm)" pass native-and-wasm-devices-initialized
emit_gate synthetic_marker_compare "$(status_for synthetic_marker_compare)" pass native-wasm-marker-set
emit_gate browser_host_prereq "$(status_for b5_host_prereq)" pass coop-coep-artifacts-persistence
emit_gate browser_runtime_prereq "$(status_for b5_runtime_prereq)" pass synthetic-browser-runtime
emit_gate real_fixture_manifest "$(status_for real_fixture_manifest)" pass local-private-fixture-handoff
emit_gate real_fixture_ready "$(status_for real_fixture_ready)" pass required-flash-hdd-and-sized-optional-assets
emit_gate real_fixture_preflight "$(status_for real_fixture_preflight)" pass real-b3-preflight
emit_gate real_b3 "${real_b3}" pass real-storage-boot-evidence
emit_gate real_b4 "${real_b4}" pass visible-display-capture
emit_gate real_b5 "${real_b5}" pass real-browser-usability
emit_gate real_b6 "${real_b6}" pass dashboard-xbe-executed-and-native-frame-match
emit_gate summary "${summary_result}" complete all-required-real-milestones

if [ "${failed}" -eq 0 ]; then
    result="pass"
else
    result="fail"
fi

printf 'BOOT_COMPLETION_AUDIT_RESULT result=%s failed=%s next=%s synthetic_native=%s synthetic_wasm=%s real_b3=%s real_b4=%s real_b5=%s real_b6=%s synthetic_dir=%s real_dir=%s\n' \
    "${result}" "${failed}" "${next_step:-unknown}" "${synthetic_native}" "${synthetic_wasm}" \
    "${real_b3}" "${real_b4}" "${real_b5}" "${real_b6}" "${synthetic_dir}" "${real_dir}"

if [ "${result}" != "pass" ] && [ "${allow_incomplete}" != "1" ]; then
    exit 1
fi
