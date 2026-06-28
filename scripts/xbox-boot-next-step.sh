#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-next-step.sh [synthetic-out-dir] [real-b3-out-dir]

Reads xbox-boot-evidence-summary.sh and prints the next concrete command for
the Xbox browser boot plan. This is a handoff helper only; it does not run the
next command.

Defaults:
  synthetic-out-dir: build-browser-boot-verify-synthetic
  real-b3-out-dir:   build-real-b3-matrix
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

tmp_summary="$(mktemp "${TMPDIR:-/tmp}/xemu-boot-next-step.XXXXXX")"
trap 'rm -f "${tmp_summary}"' EXIT

"${repo_root}/scripts/xbox-boot-evidence-summary.sh" "${synthetic_dir}" "${real_dir}" >"${tmp_summary}"

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

    line="$(grep "^BOOT_EVIDENCE item=${item} " "${tmp_summary}" || true)"
    if [ -z "${line}" ]; then
        printf 'missing'
        return
    fi
    value_for "${line}" status
}

summary_line="$(grep '^BOOT_EVIDENCE_SUMMARY ' "${tmp_summary}")"
summary_result="$(value_for "${summary_line}" result)"
next_step="$(value_for "${summary_line}" next)"
real_fixture_ready="$(status_for real_fixture_ready)"
real_b3_assets="$(status_for b3_real_assets)"
synthetic_gate="$(status_for synthetic_gate)"

result="next"
reason="${next_step}"
command=""
command_id=""

json_string() {
    local value="$1"
    local escaped

    escaped="${value//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '"%s"' "${escaped}"
}

has_fixture_layout() {
    local candidate_dir

    if [ -n "${XEMU_REAL_B3_FIXTURE_DIR:-}" ] && [ -d "${XEMU_REAL_B3_FIXTURE_DIR}" ]; then
        return 0
    fi

    if [ "${XEMU_BOOT_NEXT_IGNORE_REPO_FIXTURES:-0}" = "1" ]; then
        return 1
    fi

    for candidate_dir in "${repo_root}/fixtures" "${repo_root}/xemu-fixtures"; do
        if [ -n "${candidate_dir}" ] && [ -d "${candidate_dir}" ]; then
            return 0
        fi
    done

    return 1
}

if [ "${summary_result}" = "complete" ]; then
    result="done"
    reason="complete"
    command="XEMU_EVIDENCE_REQUIRE_COMPLETE=1 scripts/xbox-boot-evidence-summary.sh"
    command_id="audit-complete"
elif [ "${synthetic_gate}" != "pass" ]; then
    reason="synthetic-gate"
    command="scripts/xbox-browser-boot-verify-synthetic.sh"
    command_id="synthetic-gate"
else
    case "${next_step}" in
        real-b3-assets)
            case "${real_b3_assets}:${real_fixture_ready}" in
                *:fail)
                    command="scripts/xbox-real-fixtures-ready.sh"
                    command_id="real-fixtures-ready"
                    reason="fix-real-fixtures"
                    ;;
                *:missing-required|*:missing)
                    if ! has_fixture_layout; then
                        command="scripts/xbox-real-fixture-layout.sh --create"
                        command_id="real-fixture-layout"
                        reason="create-real-fixture-layout"
                    else
                        command="scripts/xbox-real-fixtures-ready.sh"
                        command_id="real-fixtures-ready"
                        reason="add-real-fixtures"
                    fi
                    ;;
                fail:*)
                    command="scripts/xbox-real-b3-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log"
                    command_id="real-b3-evidence"
                    reason="real-b3-evidence-failed"
                    ;;
                *:pass)
                    command="XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh && scripts/xbox-real-b3-matrix.sh"
                    command_id="real-b3-matrix"
                    reason="real-b3-preflight-and-matrix"
                    ;;
                *)
                    command="scripts/xbox-boot-evidence-summary.sh"
                    command_id="evidence-summary"
                    reason="unexpected-real-b3-state"
                    ;;
            esac
            ;;
        b4-visible-display)
            command="scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log"
            command_id="b4-display-evidence"
            ;;
        b5-real-browser)
            command="scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log"
            command_id="b5-browser-evidence"
            ;;
        done)
            result="done"
            reason="complete"
            command="XEMU_EVIDENCE_REQUIRE_COMPLETE=1 scripts/xbox-boot-evidence-summary.sh"
            command_id="audit-complete"
            ;;
        *)
            result="unknown"
            reason="${next_step:-missing-next}"
            command="scripts/xbox-boot-evidence-summary.sh"
            command_id="evidence-summary"
            ;;
    esac
fi

printf 'XBOX_BOOT_NEXT result=%s next=%s reason=%s command_id=%s command_json=%s command=%s synthetic_dir=%s real_dir=%s\n' \
    "${result}" "${next_step:-unknown}" "${reason}" "${command_id}" \
    "$(json_string "${command}")" "${command}" "${synthetic_dir}" "${real_dir}"
