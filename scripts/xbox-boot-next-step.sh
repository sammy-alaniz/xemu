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

    line="$(line_for "${item}")"
    if [ -z "${line}" ]; then
        printf 'missing'
        return
    fi
    value_for "${line}" status
}

line_for() {
    local item="$1"

    grep "^BOOT_EVIDENCE item=${item} " "${tmp_summary}" || true
}

repo_relative_path() {
    local path="$1"

    case "${path}" in
        "${repo_root}/"*)
            printf '%s' "${path#"${repo_root}/"}"
            ;;
        *)
            printf '%s' "${path}"
            ;;
    esac
}

summary_line="$(grep '^BOOT_EVIDENCE_SUMMARY ' "${tmp_summary}")"
summary_result="$(value_for "${summary_line}" result)"
next_step="$(value_for "${summary_line}" next)"
real_fixture_ready="$(status_for real_fixture_ready)"
real_b3_assets="$(status_for b3_real_assets)"
real_b6_dashboard="$(status_for b6_dashboard_loaded)"
real_b6_dashboard_line="$(line_for b6_dashboard_loaded)"
real_b6_dashboard_log="$(value_for "${real_b6_dashboard_line}" log)"
synthetic_gate="$(status_for synthetic_gate)"

result="next"
reason="${next_step}"
command=""
command_id=""
diagnostic_command=""
diagnostic_command_id="none"
diagnostic_reason="none"

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
        b6-dashboard-loaded)
            if [ "${real_b6_dashboard}" = "missing" ]; then
                reason="b6-dashboard-evidence-missing"
            else
                reason="b6-dashboard-evidence-failed"
            fi
            preferred_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log"
            if [ -f "${preferred_b6_dashboard_log}" ]; then
                real_b6_dashboard_log="${preferred_b6_dashboard_log}"
            fi
            if [ -z "${real_b6_dashboard_log}" ]; then
                real_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log"
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-v2-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-ready-edge-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-precommit-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-memory-watch-write-0x3a890-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-memory-sample-0x3a890-full-baseline-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-pretransition-then-empty-filtered-limit4-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-headless-gate-bounded-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v2-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v2.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-timeout-300s-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-timeout-300s-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-v1.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-pm-ac97-callback-v1-combined.log"
                fi
                if [ ! -f "${real_b6_dashboard_log}" ]; then
                    real_b6_dashboard_log="${real_dir}/browser-runtime-firefox-bidi-irq-source-v6-combined.log"
                fi
            fi
            b6_native_log="${real_dir}/native-headless-graphic-update-v2/boot-smoke.log"
            if [ ! -f "${b6_native_log}" ]; then
                b6_native_log="${real_dir}/native-post-iret-flow-v1/boot-smoke.log"
            fi
            command="scripts/xbox-dashboard-loaded-evidence-check.sh $(repo_relative_path "${real_b6_dashboard_log}")"
            command_id="b6-dashboard-loaded-evidence"
            diagnostic_command="scripts/xbox-b6-current-boundary.sh --native-log $(repo_relative_path "${b6_native_log}") --browser-log $(repo_relative_path "${real_b6_dashboard_log}")"
            diagnostic_command_id="b6-current-boundary"
            diagnostic_reason="converge-browser-post-service-flow"
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

printf 'XBOX_BOOT_NEXT result=%s next=%s reason=%s command_id=%s command_json=%s command=%s diagnostic_command_id=%s diagnostic_reason=%s diagnostic_command_json=%s diagnostic_command=%s synthetic_dir=%s real_dir=%s\n' \
    "${result}" "${next_step:-unknown}" "${reason}" "${command_id}" \
    "$(json_string "${command}")" "${command}" \
    "${diagnostic_command_id}" "${diagnostic_reason}" \
    "$(json_string "${diagnostic_command}")" "${diagnostic_command}" \
    "${synthetic_dir}" "${real_dir}"
