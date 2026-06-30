#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-boot-evidence-report.sh [output.md] [synthetic-out-dir] [real-b3-out-dir]

Generates a Markdown status report from xbox-boot-evidence-summary.sh. The
report is intended for handoff: it separates proven synthetic evidence from
real-asset B3/B4/B5 gaps and records the next command to run.

Defaults:
  output.md:         xbox-browser-boot-status.md
  synthetic-out-dir: build-browser-boot-verify-synthetic
  real-b3-out-dir:   build-real-b3-matrix
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
output="${1:-${repo_root}/xbox-browser-boot-status.md}"
synthetic_dir="${2:-${repo_root}/build-browser-boot-verify-synthetic}"
real_dir="${3:-${repo_root}/build-real-b3-matrix}"

case "${output}" in
    /*) ;;
    *) output="${repo_root}/${output}" ;;
esac
case "${synthetic_dir}" in
    /*) ;;
    *) synthetic_dir="${repo_root}/${synthetic_dir}" ;;
esac
case "${real_dir}" in
    /*) ;;
    *) real_dir="${repo_root}/${real_dir}" ;;
esac

tmp_summary="$(mktemp "${TMPDIR:-/tmp}/xemu-boot-evidence-summary.XXXXXX")"
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

path_for_line() {
    local line="$1"

    printf '%s' "${line}" | sed -n 's/.* path=//p'
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

latest_line() {
    local file="$1"
    local pattern="$2"

    if [ ! -f "${file}" ]; then
        return
    fi
    grep -E "${pattern}" "${file}" | tr -d '\r' | tail -n 1 || true
}

first_matching_line() {
    local file="$1"
    local pattern="$2"

    if [ ! -f "${file}" ]; then
        return
    fi
    awk -v pattern="${pattern}" '
        $0 ~ pattern {
            gsub(/\r/, "")
            print
            exit
        }
    ' "${file}" || true
}

first_line() {
    printf '%s\n' "$1" | sed -n '1p'
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

count_lines() {
    local file="$1"
    local pattern="$2"

    if [ ! -f "${file}" ]; then
        printf '0'
        return
    fi

    awk -v pattern="${pattern}" '$0 ~ pattern { count++ } END { print count + 0 }' "${file}"
}

next_command_line() {
    "${repo_root}/scripts/xbox-boot-next-step.sh" "${synthetic_dir}" "${real_dir}" 2>/dev/null || true
}

summary_line="$(grep '^BOOT_EVIDENCE_SUMMARY ' "${tmp_summary}")"
summary_result="$(value_for "${summary_line}" result)"
synthetic_native="$(value_for "${summary_line}" synthetic_native)"
synthetic_wasm="$(value_for "${summary_line}" synthetic_wasm)"
real_b3="$(value_for "${summary_line}" real_b3)"
real_b4="$(value_for "${summary_line}" real_b4)"
real_b5="$(value_for "${summary_line}" real_b5)"
next_step="$(value_for "${summary_line}" next)"
real_readiness_log="$(value_for "$(grep '^BOOT_EVIDENCE item=real_fixture_ready ' "${tmp_summary}" || true)" log)"
real_log="$(value_for "$(grep '^BOOT_EVIDENCE item=b3_real_assets ' "${tmp_summary}" || true)" log)"
real_b6_log="$(value_for "$(grep '^BOOT_EVIDENCE item=b6_dashboard_loaded ' "${tmp_summary}" || true)" log)"
flash_line="$(latest_line "${real_readiness_log}" '^REAL_FIXTURE_READY item=flash ')"
hdd_line="$(latest_line "${real_readiness_log}" '^REAL_FIXTURE_READY item=hdd ')"
mcpx_line="$(latest_line "${real_readiness_log}" '^REAL_FIXTURE_READY item=mcpx ')"
eeprom_line="$(latest_line "${real_readiness_log}" '^REAL_FIXTURE_READY item=eeprom ')"
hdd_path_for_b6="$(path_for_line "${hdd_line}")"
real_b3_failure_line="$(latest_line "${real_log}" '^REAL_B3_EVIDENCE result=fail|^BOOT_REAL_B3_MATRIX_RESULT result=fail')"
display_failure_line="$(latest_line "${real_log}" '^DISPLAY_CAPTURE_EVIDENCE result=fail')"
runtime_failure_line="$(latest_line "${real_log}" '^BROWSER_RUNTIME_EVIDENCE result=fail')"
dashboard_xbe_read_line="$(latest_line "${real_dir}/dashboard-xbe-read.log" '^DASHBOARD_XBE_READ_EVIDENCE ')"
dashboard_xbe_browser_line="$(latest_line "${real_dir}/dashboard-xbe-read-browser-runtime.log" '^DASHBOARD_XBE_READ_EVIDENCE ')"
dashboard_xbe_playwright_long_line=""
if [ -f "${real_dir}/browser-runtime-playwright-300s.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_playwright_long_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-playwright-300s.log" \
        --default-context browser-runtime 2>&1 || true)")"
fi
playwright_firefox_runtime_line="$(latest_line "${real_dir}/browser-runtime-playwright-firefox.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_playwright_firefox_line=""
if [ -f "${real_dir}/browser-runtime-playwright-firefox.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_playwright_firefox_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-playwright-firefox.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
firefox_bidi_long_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-300s.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_long_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-300s.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_long_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-300s.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
firefox_bidi_ide_poll_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-ide-poll.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_ide_poll_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-ide-poll.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_ide_poll_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-ide-poll.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
firefox_bidi_virtual_probe_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_virtual_probe_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_virtual_probe_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_virtual_probe_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe.log" '^BOOT_MARK b6 dashboard=xbe-virtual-probe ')"
firefox_bidi_page_probe_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_page_probe_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_page_probe_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_virtual_page_probe_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe.log" '^BOOT_MARK b6 dashboard=xbe-virtual-probe ')"
firefox_bidi_read_progress_loaded_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_read_progress_loaded_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_read_progress_loaded_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_read_progress_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" '^BOOT_MARK b6 dashboard=xbe-read-progress ')"
dashboard_xbe_loaded_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
firefox_bidi_exec_probe_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_exec_probe_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_exec_probe_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_exec_probe_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" '^BOOT_MARK b6 dashboard=xbe-exec-probe ')"
dashboard_xbe_loaded_firefox_bidi_exec_probe_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_exec_probe_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
firefox_bidi_ret_target_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_ret_target_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_ret_target_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_exec_ret_target_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" '^BOOT_MARK b6 dashboard=xbe-exec-probe ')"
dashboard_xbe_loaded_firefox_bidi_ret_target_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_ret_target_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
firefox_bidi_transition_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_transition_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_transition_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_transition_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" '^BOOT_MARK b6 dashboard=xbe-exec-transition ')"
dashboard_xbe_loaded_firefox_bidi_transition_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_transition_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
firefox_bidi_edge_runtime_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_edge_line=""
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_edge_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_edge_firefox_bidi_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" '^BOOT_MARK b6 dashboard=xbe-exec-edge ')"
dashboard_xbe_loaded_firefox_bidi_edge_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_edge_line="$(latest_line "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
branch_target_log="${real_dir}/browser-runtime-firefox-bidi-xbe-branch-target-classification.log"
branch_target_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-branch-target-classification-combined.log"
branch_target_label="classification"
if [ ! -f "${branch_target_log}" ]; then
    branch_target_log="${real_dir}/browser-runtime-firefox-bidi-xbe-branch-target-probe-wide-edge.log"
    branch_target_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-branch-target-probe-wide-edge-combined.log"
    branch_target_label="wide-edge"
fi
firefox_bidi_branch_target_runtime_line="$(latest_line "${branch_target_log}" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_branch_target_line=""
if [ -f "${branch_target_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_branch_target_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${branch_target_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_branch_target_mem_firefox_bidi_line="$(latest_line "${branch_target_log}" 'next_branch_kind=call-mem32|branch_kind=call-mem32')"
dashboard_branch_target_reg_firefox_bidi_line="$(latest_line "${branch_target_log}" 'next_branch_kind=call-reg|branch_kind=call-reg')"
dashboard_edge_branch_target_firefox_bidi_line="$(latest_line "${branch_target_log}" '^BOOT_MARK b6 dashboard=xbe-exec-edge ')"
dashboard_xbe_loaded_firefox_bidi_branch_target_line="$(latest_line "${branch_target_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_branch_target_line="$(latest_line "${branch_target_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
entry_probe_log="${real_dir}/browser-runtime-firefox-bidi-xbe-entry-probe.log"
entry_probe_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-entry-probe-combined.log"
firefox_bidi_entry_probe_runtime_line="$(latest_line "${entry_probe_log}" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_entry_probe_line=""
if [ -f "${entry_probe_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_entry_probe_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${entry_probe_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_entry_probe_firefox_bidi_line="$(latest_line "${entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe ')"
dashboard_entry_probe_ready_firefox_bidi_line="$(latest_line "${entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready')"
dashboard_xbe_loaded_firefox_bidi_entry_probe_line="$(latest_line "${entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_entry_probe_line="$(latest_line "${entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
entry_target_log="${real_dir}/browser-runtime-firefox-bidi-xbe-entry-target-probe.log"
entry_target_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-entry-target-probe-combined.log"
firefox_bidi_entry_target_runtime_line="$(latest_line "${entry_target_log}" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_entry_target_line=""
if [ -f "${entry_target_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_entry_target_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${entry_target_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_entry_target_firefox_bidi_line="$(latest_line "${entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-entry-target-probe ')"
dashboard_entry_target_near_unknown_firefox_bidi_line="$(latest_line "${entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-entry-target-probe .*target_status=near-phys-unknown')"
dashboard_xbe_loaded_firefox_bidi_entry_target_line="$(latest_line "${entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_entry_target_line="$(latest_line "${entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
browser_phys_compare_log="${real_dir}/browser-runtime-firefox-bidi-phys-compare.log"
browser_phys_compare_runtime_line="$(latest_line "${browser_phys_compare_log}" '^BROWSER_RUNTIME_SMOKE ')"
browser_phys_compare_line="$(latest_line "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare ')"
browser_phys_compare_match_line="$(latest_line "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare .*result=match')"
browser_phys_compare_count="$(count_lines "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare ')"
browser_phys_compare_no_match_count="$(count_lines "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare .*result=no-match')"
browser_phys_compare_loaded_line="$(latest_line "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
browser_phys_compare_entry_ready_line="$(latest_line "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready')"
browser_phys_compare_executed_line="$(latest_line "${browser_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_tcg_exec_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-tcg-exec/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_tcg_exec_executed_line="$(latest_line "${real_dir}/native-60s-xbe-tcg-exec/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_exec_probe_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-stride10k/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-exec-probe ')"
native_exec_probe_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-stride10k/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_exec_probe_executed_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-stride10k/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_high_alias_exec_probe_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-cpu-context/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-exec-probe ')"
native_high_alias_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-cpu-context/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_high_alias_executed_line="$(latest_line "${real_dir}/native-60s-xbe-exec-probe-cpu-context/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_ret_target_exec_probe_line="$(latest_line "${real_dir}/native-60s-xbe-exec-ret-target-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-exec-probe ')"
native_ret_target_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-exec-ret-target-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_ret_target_executed_line="$(latest_line "${real_dir}/native-60s-xbe-exec-ret-target-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_transition_exec_probe_line="$(latest_line "${real_dir}/native-60s-xbe-exec-transition-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-exec-transition ')"
native_transition_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-exec-transition-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_transition_executed_line="$(latest_line "${real_dir}/native-60s-xbe-exec-transition-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_edge_exec_probe_line="$(latest_line "${real_dir}/native-60s-xbe-exec-edge-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-exec-edge ')"
native_edge_loaded_line="$(latest_line "${real_dir}/native-60s-xbe-exec-edge-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_edge_executed_line="$(latest_line "${real_dir}/native-60s-xbe-exec-edge-probe/boot-smoke.log" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_branch_target_log="${real_dir}/native-60s-xbe-branch-target-classification/boot-smoke.log"
if [ ! -f "${native_branch_target_log}" ]; then
    native_branch_target_log="${real_dir}/native-60s-xbe-branch-target-probe/boot-smoke.log"
fi
native_branch_target_mem_line="$(latest_line "${native_branch_target_log}" 'next_branch_kind=call-mem32|branch_kind=call-mem32')"
native_branch_target_reg_line="$(latest_line "${native_branch_target_log}" 'next_branch_kind=call-reg|branch_kind=call-reg')"
native_branch_target_loaded_line="$(latest_line "${native_branch_target_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_branch_target_executed_line="$(latest_line "${native_branch_target_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_entry_probe_log="${real_dir}/native-60s-xbe-entry-probe-v2/boot-smoke.log"
native_entry_probe_line="$(latest_line "${native_entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe ')"
native_entry_probe_ready_line="$(latest_line "${native_entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready')"
native_entry_probe_loaded_line="$(latest_line "${native_entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_entry_probe_executed_line="$(latest_line "${native_entry_probe_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_entry_target_log="${real_dir}/native-60s-xbe-entry-target-probe/boot-smoke.log"
native_entry_target_line="$(latest_line "${native_entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-entry-target-probe ')"
native_entry_target_near_unknown_line="$(latest_line "${native_entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-entry-target-probe .*target_status=near-phys-unknown')"
native_entry_target_loaded_line="$(latest_line "${native_entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_entry_target_executed_line="$(latest_line "${native_entry_target_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_phys_compare_log="${real_dir}/native-20s-xbe-phys-compare/boot-smoke.log"
native_phys_compare_line="$(latest_line "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare ')"
native_phys_compare_match_line="$(latest_line "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare .*result=match')"
native_phys_compare_count="$(count_lines "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare ')"
native_phys_compare_no_match_count="$(count_lines "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-phys-compare .*result=no-match')"
native_phys_compare_loaded_line="$(latest_line "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_phys_compare_entry_ready_line="$(latest_line "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready')"
native_phys_compare_executed_line="$(latest_line "${native_phys_compare_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
dispatch_probe_log="${real_dir}/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3.log"
dispatch_probe_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3-combined.log"
dispatch_probe_label="dispatch-v3"
if [ ! -f "${dispatch_probe_log}" ]; then
    dispatch_probe_log="${real_dir}/browser-runtime-firefox-bidi-xbe-dispatch-probe.log"
    dispatch_probe_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-dispatch-probe-combined.log"
    dispatch_probe_label="dispatch"
fi
firefox_bidi_dispatch_probe_runtime_line="$(latest_line "${dispatch_probe_log}" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_dispatch_probe_line=""
if [ -f "${dispatch_probe_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_dispatch_probe_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${dispatch_probe_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_dispatch_probe_firefox_bidi_line="$(latest_line "${dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-dispatch-probe ')"
dashboard_dispatch_probe_no_reg_firefox_bidi_line="$(latest_line "${dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-dispatch-probe .*reg_phys_match_count=0 .*reg_entry_near_count=0')"
dashboard_xbe_loaded_firefox_bidi_dispatch_probe_line="$(latest_line "${dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_dispatch_probe_line="$(latest_line "${dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_dispatch_probe_log="${real_dir}/native-60s-xbe-dispatch-probe-v3/boot-smoke.log"
if [ ! -f "${native_dispatch_probe_log}" ]; then
    native_dispatch_probe_log="${real_dir}/native-60s-xbe-dispatch-probe/boot-smoke.log"
fi
native_dispatch_probe_line="$(latest_line "${native_dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-dispatch-probe ')"
native_dispatch_probe_no_reg_line="$(latest_line "${native_dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-dispatch-probe .*reg_phys_match_count=0 .*reg_entry_near_count=0')"
native_dispatch_probe_loaded_line="$(latest_line "${native_dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_dispatch_probe_executed_line="$(latest_line "${native_dispatch_probe_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pm-ac97-callback-v1.log"
kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pm-ac97-callback-v1-combined.log"
kernel_loop_label="PM timer / AC97 callback probe"
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-irq-source-v6.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-irq-source-v6-combined.log"
    kernel_loop_label="IRQ-source PM/AC97 arming probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-irq-source-v4.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-irq-source-v4-combined.log"
    kernel_loop_label="IRQ-source interrupt-flow probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-irq-watch-route-v3.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-irq-watch-route-v3-combined.log"
    kernel_loop_label="IRQ-watch route interrupt-flow probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pic-ack-serviceable-lowpic-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pic-ack-serviceable-lowpic-v1-combined.log"
    kernel_loop_label="PIC-ack serviceable idle-loop interrupt-flow probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-timer-pump-serviceable-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-timer-pump-serviceable-v1-combined.log"
    kernel_loop_label="serviceable idle-loop interrupt-flow probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-timer-pump-idle-loop-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-timer-pump-idle-loop-v1-combined.log"
    kernel_loop_label="idle-loop timer-pump IRET-frame probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-iret-frame-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-iret-frame-v1-combined.log"
    kernel_loop_label="IRET-frame PCRTC-off probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-hard-irq-service-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-hard-irq-service-v1-combined.log"
    kernel_loop_label="Hard-IRQ service PCRTC-off probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-tcg-timer-pump-pcrtc-off-v2.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-tcg-timer-pump-pcrtc-off-v2-combined.log"
    kernel_loop_label="TCG timer-pump PCRTC-off probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pcrtc-vblank-off-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pcrtc-vblank-off-v1-combined.log"
    kernel_loop_label="PCRTC vblank off probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pcrtc-vblank-suppress-entry-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pcrtc-vblank-suppress-entry-v1-combined.log"
    kernel_loop_label="PCRTC vblank suppress-until-entry probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pmc-cpu-context-v1.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pmc-cpu-context-v1-combined.log"
    kernel_loop_label="PMC CPU-context probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-after-idle-v2.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-after-idle-v2-combined.log"
    kernel_loop_label="PFIFO/PGRAPH after-idle probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-after-idle.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-after-idle-combined.log"
    kernel_loop_label="PFIFO/PGRAPH after-idle probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-command-window-v2.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-command-window-v2-combined.log"
    kernel_loop_label="PFIFO/PGRAPH command-window probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-command-window.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-command-window-combined.log"
    kernel_loop_label="PFIFO/PGRAPH command-window probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-clear.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-clear-combined.log"
    kernel_loop_label="PGRAPH notify-clear probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-alias-compare.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-alias-compare-combined.log"
    kernel_loop_label="alias-compare probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-post-entry-diag.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-post-entry-diag-combined.log"
    kernel_loop_label="post-entry diagnostic probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-browser-irq-pmc-limits.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-browser-irq-pmc-limits-combined.log"
    kernel_loop_label="browser IRQ/PMC limits probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-probe-90s.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-probe-90s-combined.log"
    kernel_loop_label="PGRAPH notify-error probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-notify-probe-combined.log"
    kernel_loop_label="PGRAPH notify-error probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-irq-line-low-priority-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-irq-line-low-priority-probe-combined.log"
    kernel_loop_label="PGRAPH IRQ-line low-priority probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-irq-line-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-pgraph-irq-line-probe-combined.log"
    kernel_loop_label="PGRAPH IRQ-line probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-wait-state-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-wait-state-probe-combined.log"
    kernel_loop_label="wait-state probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pgraph-method-probe-v3.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pgraph-method-probe-v3-combined.log"
    kernel_loop_label="PGRAPH-method probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pgraph-method-probe-v2.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pgraph-method-probe-v2-combined.log"
    kernel_loop_label="PGRAPH-method probe v2"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pfifo-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pfifo-probe-combined.log"
    kernel_loop_label="PFIFO/IRQ-source probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-irq-source-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-irq-source-probe-combined.log"
    kernel_loop_label="IRQ-source probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pmc-probe.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-pmc-probe-combined.log"
    kernel_loop_label="PMC interrupt probe"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-memclass.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-memclass-combined.log"
    kernel_loop_label="kernel-loop memclass"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-memdecode.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-memdecode-combined.log"
    kernel_loop_label="kernel-loop memdecode"
fi
if [ ! -f "${kernel_loop_log}" ]; then
    kernel_loop_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-transition-sample.log"
    kernel_loop_combined_log="${real_dir}/browser-runtime-firefox-bidi-xbe-kernel-loop-transition-sample-combined.log"
    kernel_loop_label="kernel-loop transition sample"
fi
firefox_bidi_kernel_loop_runtime_line="$(latest_line "${kernel_loop_log}" '^BROWSER_RUNTIME_TRANSCRIPT ')"
dashboard_xbe_firefox_bidi_kernel_loop_line=""
if [ -f "${kernel_loop_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_xbe_firefox_bidi_kernel_loop_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-read-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${kernel_loop_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_kernel_loop_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe ')"
dashboard_kernel_loop_firefox_bidi_wait_state_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe .*nv2a_wait_present=yes')"
dashboard_kernel_loop_firefox_bidi_self_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe .*probe=transition-sample .*loop_kind=self')"
dashboard_alias_compare_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-alias-compare ')"
dashboard_alias_compare_no_match_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-alias-compare .*code_hash_match=no')"
dashboard_alias_hash_evidence_line=""
if [ -f "${kernel_loop_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_alias_hash_evidence_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-hash-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${kernel_loop_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
target_hash_log="${real_dir}/browser-runtime-firefox-bidi-target-hash-v1.log"
dashboard_target_hash_evidence_line=""
if [ -f "${target_hash_log}" ] &&
   [ -n "${hdd_path_for_b6}" ] &&
   [ -f "${hdd_path_for_b6}" ]; then
    dashboard_target_hash_evidence_line="$(first_line "$("${repo_root}/scripts/xbox-dashboard-xbe-hash-evidence.py" \
        --hdd "${hdd_path_for_b6}" \
        --log "${target_hash_log}" \
        --require-context browser-runtime 2>&1 || true)")"
fi
dashboard_pmc_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=pmc-access ')"
dashboard_pmc_firefox_bidi_pcrtc_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=pmc-access .*pmc_pending_after=0x01000000')"
dashboard_irq_source_firefox_bidi_pcrtc_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-source .*source=pcrtc')"
dashboard_irq_source_firefox_bidi_pgraph_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-source .*source=pgraph')"
dashboard_irq_line_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-line ')"
dashboard_pcrtc_vblank_gate_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 nv2a=pcrtc-vblank-gate ')"
dashboard_pfifo_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress ')"
dashboard_pfifo_firefox_bidi_puller_method_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress .*op=puller-method ')"
dashboard_pfifo_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress ')"
dashboard_pfifo_firefox_bidi_context_wait_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress .*waiting_context=yes')"
dashboard_pfifo_window_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=window ')"
dashboard_pfifo_window_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pfifo=window ')"
dashboard_pgraph_method_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=method ')"
dashboard_pgraph_method_window_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=method-window ')"
dashboard_pgraph_method_window_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=method-window ')"
dashboard_pgraph_method_firefox_bidi_nop_notify_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=method .*phase=exit .*method=0x0100 .*pending=0x00100000 .*waiting_nop=yes')"
dashboard_pgraph_notify_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-error ')"
dashboard_pgraph_notify_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-error ')"
dashboard_pgraph_notify_clear_firefox_bidi_count="$(count_lines "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-clear ')"
dashboard_pgraph_notify_clear_firefox_bidi_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-clear ')"
dashboard_xbe_loaded_firefox_bidi_kernel_loop_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
dashboard_xbe_executed_firefox_bidi_kernel_loop_line="$(latest_line "${kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
native_kernel_loop_log="${real_dir}/native-120s-irq-source-v3/boot-smoke.log"
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-irq-source-v2/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-irq-watch-route-v1/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-pic-ack-serviceable-lowpic-v1/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-iret-frame-v1/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-pmc-cpu-context-v1/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-after-idle-probe-v2/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-after-idle-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-command-window-null-flip-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-command-window-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-120s-pgraph-notify-clear-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-pgraph-notify-clear-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-pgraph-notify-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-30s-pgraph-notify-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-30s-pgraph-irq-line-low-priority-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-30s-pgraph-irq-line-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-30s-xbe-wait-state-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-pgraph-method-probe-v2/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-pgraph-method-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-pfifo-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-irq-source-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-pmc-probe/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-kernel-loop-memclass/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-kernel-loop-memdecode/boot-smoke.log"
fi
if [ ! -f "${native_kernel_loop_log}" ]; then
    native_kernel_loop_log="${real_dir}/native-60s-xbe-kernel-loop-transition-sample/boot-smoke.log"
fi
native_kernel_loop_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe ')"
native_kernel_loop_wait_state_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe .*nv2a_wait_present=yes')"
native_kernel_loop_transition_self_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe .*probe=transition-sample .*loop_kind=self')"
native_kernel_loop_edge_self_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=kernel-loop-probe .*probe=edge .*loop_kind=self')"
native_pmc_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 nv2a=pmc-access ')"
native_pmc_pgraph_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 nv2a=pmc-access .*pmc_pending_after=0x00001000')"
native_irq_source_pgraph_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-source .*source=pgraph')"
native_irq_source_pcrtc_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-source .*source=pcrtc')"
native_irq_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 nv2a=irq-line ')"
native_pfifo_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress ')"
native_pfifo_puller_method_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress .*op=puller-method ')"
native_pfifo_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress ')"
native_pfifo_context_wait_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=progress .*waiting_context=yes')"
native_pfifo_window_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=window ')"
native_pfifo_window_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pfifo=window ')"
native_pgraph_method_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=method ')"
native_pgraph_method_window_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=method-window ')"
native_pgraph_method_window_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=method-window ')"
native_pgraph_method_nop_notify_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=method .*phase=exit .*method=0x0100 .*pending=0x00100000 .*waiting_nop=yes')"
native_pgraph_notify_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-error ')"
native_pgraph_notify_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-error ')"
native_pgraph_notify_clear_count="$(count_lines "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-clear ')"
native_pgraph_notify_clear_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 pgraph=notify-clear ')"
native_kernel_loop_loaded_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
native_kernel_loop_executed_line="$(latest_line "${native_kernel_loop_log}" '^BOOT_MARK b6 dashboard=xbe-executed ')"
pgraph_command_stream_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    pgraph_command_stream_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pgraph-command-stream-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
post_command_handoff_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    post_command_handoff_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-handoff-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
post_command_loop_clusters_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    post_command_loop_clusters_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
post_command_irq_state_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    post_command_irq_state_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-irq-state-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
pcrtc_vblank_divergence_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    pcrtc_vblank_divergence_line="$(first_line "$("${repo_root}/scripts/xbox-pcrtc-vblank-divergence.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
iret_frame_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    iret_frame_compare_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
post_idle_interrupt_flow_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${kernel_loop_log}" ]; then
    post_idle_interrupt_flow_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${kernel_loop_log}" 2>&1 || true)")"
fi
timer_pump_attribution_log="${real_dir}/browser-runtime-firefox-bidi-timer-pump-attribution-v2.log"
timer_pump_attribution_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${timer_pump_attribution_log}" ]; then
    timer_pump_attribution_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${timer_pump_attribution_log}" 2>&1 || true)")"
fi
timer_pump_attribution_runtime_line="$(latest_line "${timer_pump_attribution_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_only_timer_pump_log="${real_dir}/browser-runtime-firefox-bidi-pit-only-pump-v1.log"
pit_only_timer_pump_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${pit_only_timer_pump_log}" ]; then
    pit_only_timer_pump_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${pit_only_timer_pump_log}" 2>&1 || true)")"
fi
pit_only_timer_pump_runtime_line="$(latest_line "${pit_only_timer_pump_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_after_idle_timer_pump_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-pump-v1.log"
pit_after_idle_timer_pump_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${pit_after_idle_timer_pump_log}" ]; then
    pit_after_idle_timer_pump_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${pit_after_idle_timer_pump_log}" 2>&1 || true)")"
fi
pit_after_idle_timer_pump_runtime_line="$(latest_line "${pit_after_idle_timer_pump_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_after_idle_full_timer_pump_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-v1.log"
pit_after_idle_full_timer_pump_compare_line="not reported"
if [ -f "${native_kernel_loop_log}" ] && [ -f "${pit_after_idle_full_timer_pump_log}" ]; then
    pit_after_idle_full_timer_pump_compare_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_kernel_loop_log}" \
        --browser-log "${pit_after_idle_full_timer_pump_log}" 2>&1 || true)")"
fi
pit_after_idle_full_timer_pump_runtime_line="$(latest_line "${pit_after_idle_full_timer_pump_log}" '^BROWSER_RUNTIME_SMOKE ')"
native_pfifo_boundary_log="${real_dir}/native-pfifo-boundary-v1/boot-smoke.log"
pfifo_boundary_timer_pump_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-boundary-pit-after-idle-full-v1.log"
pfifo_stream_idle_boundary_compare_line="not reported"
if [ -f "${native_pfifo_boundary_log}" ] && [ -f "${pfifo_boundary_timer_pump_log}" ]; then
    pfifo_stream_idle_boundary_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-stream-idle-boundary-compare.py" \
        --native-log "${native_pfifo_boundary_log}" \
        --browser-log "${pfifo_boundary_timer_pump_log}" 2>&1 || true)")"
fi
pfifo_boundary_timer_pump_runtime_line="$(latest_line "${pfifo_boundary_timer_pump_log}" '^BROWSER_RUNTIME_SMOKE ')"
native_pfifo_transition_log="${real_dir}/native-pfifo-activity-v1/boot-smoke.log"
pfifo_transition_timer_pump_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-activity-v1.log"
pfifo_stream_idle_transition_compare_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_timer_pump_log}" ]; then
    pfifo_stream_idle_transition_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-stream-idle-boundary-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_timer_pump_log}" 2>&1 || true)")"
fi
pfifo_transition_irq_timing_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_timer_pump_log}" ]; then
    pfifo_transition_irq_timing_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_timer_pump_log}" 2>&1 || true)")"
fi
pfifo_transition_timer_pump_runtime_line="$(latest_line "${pfifo_transition_timer_pump_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_pit_at_transition_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-transition-pit-at-transition-v1.log"
pfifo_transition_pit_at_transition_compare_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_pit_at_transition_log}" ]; then
    pfifo_transition_pit_at_transition_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-stream-idle-boundary-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_pit_at_transition_log}" 2>&1 || true)")"
fi
pfifo_transition_pit_at_transition_flow_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_pit_at_transition_log}" ]; then
    pfifo_transition_pit_at_transition_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_pit_at_transition_log}" 2>&1 || true)")"
fi
pfifo_transition_pit_at_transition_runtime_line="$(latest_line "${pfifo_transition_pit_at_transition_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_gate_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-before-transition-v3.log"
pfifo_transition_gate_runtime_line="$(latest_line "${pfifo_transition_gate_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_gate_line="$(first_matching_line "${pfifo_transition_gate_log}" 'BOOT_MARK b6 tcg=timer-pump-gate ')"
pfifo_transition_gate_compare_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_gate_log}" ]; then
    pfifo_transition_gate_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_gate_log}" 2>&1 || true)")"
fi
pfifo_transition_activity_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-before-transition-activity-v1.log"
pfifo_transition_activity_runtime_line="$(latest_line "${pfifo_transition_activity_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_activity_gate_line="$(first_matching_line "${pfifo_transition_activity_log}" 'BOOT_MARK b6 tcg=timer-pump-gate .* ready=yes ')"
pfifo_transition_activity_timer_line="$(first_matching_line "${pfifo_transition_activity_log}" 'BOOT_MARK b6 tcg=timer-pump ')"
pfifo_transition_activity_compare_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_activity_log}" ]; then
    pfifo_transition_activity_compare_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_activity_log}" 2>&1 || true)")"
fi
pfifo_transition_activity_flow_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_activity_log}" ]; then
    pfifo_transition_activity_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_activity_log}" 2>&1 || true)")"
fi
pfifo_transition_defer_to_idle_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-defer-to-idle-v1.log"
pfifo_transition_defer_to_idle_runtime_line="$(latest_line "${pfifo_transition_defer_to_idle_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_defer_to_idle_dashboard_line="not reported"
if [ -f "${pfifo_transition_defer_to_idle_log}" ]; then
    pfifo_transition_defer_to_idle_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${pfifo_transition_defer_to_idle_log}" 2>&1 || true)"
fi
pfifo_transition_defer_to_idle_irq_timing_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_defer_to_idle_log}" ]; then
    pfifo_transition_defer_to_idle_irq_timing_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_defer_to_idle_log}" 2>&1 || true)")"
fi
pfifo_transition_defer_to_idle_flow_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_defer_to_idle_log}" ]; then
    pfifo_transition_defer_to_idle_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_defer_to_idle_log}" 2>&1 || true)")"
fi
pfifo_transition_pre_commit_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-pre-commit-pit-v2.log"
pfifo_transition_pre_commit_runtime_line="$(latest_line "${pfifo_transition_pre_commit_log}" '^BROWSER_RUNTIME_SMOKE ')"
pfifo_transition_pre_commit_dashboard_line="not reported"
if [ -f "${pfifo_transition_pre_commit_log}" ]; then
    pfifo_transition_pre_commit_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${pfifo_transition_pre_commit_log}" 2>&1 || true)"
fi
pfifo_transition_pre_commit_marker_line="$(first_matching_line "${pfifo_transition_pre_commit_log}" 'BOOT_MARK b6 pfifo=pre-commit-timer-pump ')"
pfifo_transition_pre_commit_irq_timing_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_pre_commit_log}" ]; then
    pfifo_transition_pre_commit_irq_timing_line="$(first_line "$("${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_pre_commit_log}" 2>&1 || true)")"
fi
pfifo_transition_pre_commit_flow_line="not reported"
if [ -f "${native_pfifo_transition_log}" ] && [ -f "${pfifo_transition_pre_commit_log}" ]; then
    pfifo_transition_pre_commit_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_pfifo_transition_log}" \
        --browser-log "${pfifo_transition_pre_commit_log}" 2>&1 || true)")"
fi
native_post_iret_log="${real_dir}/native-post-iret-flow-v1/boot-smoke.log"
native_post_iret_summary_line="$(latest_line "${native_post_iret_log}" '^BOOT_SMOKE_SUMMARY ')"
native_post_iret_metric_line="$(latest_line "${native_post_iret_log}" '^BOOT_SMOKE_METRIC ')"
pit_after_idle_full_post_iret_v4_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v4.log"
pit_after_idle_full_post_iret_v4_runtime_line="$(latest_line "${pit_after_idle_full_post_iret_v4_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_after_idle_full_post_iret_v4_dashboard_line="not reported"
if [ -f "${pit_after_idle_full_post_iret_v4_log}" ]; then
    pit_after_idle_full_post_iret_v4_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${pit_after_idle_full_post_iret_v4_log}" 2>&1 || true)"
fi
pit_after_idle_full_post_iret_v4_iret_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v4_log}" ]; then
    pit_after_idle_full_post_iret_v4_iret_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v4_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_v4_loop_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v4_log}" ]; then
    pit_after_idle_full_post_iret_v4_loop_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v4_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_v4_flow_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v4_log}" ]; then
    pit_after_idle_full_post_iret_v4_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v4_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_v5_raw_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5.log"
pit_after_idle_full_post_iret_v5_combined_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5-combined.log"
pit_after_idle_full_post_iret_v5_log="${pit_after_idle_full_post_iret_v5_combined_log}"
if [ ! -f "${pit_after_idle_full_post_iret_v5_log}" ]; then
    pit_after_idle_full_post_iret_v5_log="${pit_after_idle_full_post_iret_v5_raw_log}"
fi
pit_after_idle_full_post_iret_v5_runtime_line="$(latest_line "${pit_after_idle_full_post_iret_v5_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_after_idle_full_post_iret_v5_runtime_evidence_line="not reported"
pit_after_idle_full_post_iret_v5_display_line="not reported"
pit_after_idle_full_post_iret_v5_dashboard_line="not reported"
pit_after_idle_full_post_iret_v5_read_progress_line="$(latest_line "${pit_after_idle_full_post_iret_v5_log}" '^BOOT_MARK b6 dashboard=xbe-read-progress ')"
pit_after_idle_full_post_iret_v5_read_complete_line="$(latest_line "${pit_after_idle_full_post_iret_v5_log}" '^BOOT_MARK b6 dashboard=xbe-read-complete ')"
pit_after_idle_full_post_iret_v5_loaded_line="$(latest_line "${pit_after_idle_full_post_iret_v5_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
pit_after_idle_full_post_iret_v5_entry_ready_line="$(latest_line "${pit_after_idle_full_post_iret_v5_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .* status=ready ')"
if [ -f "${pit_after_idle_full_post_iret_v5_log}" ]; then
    pit_after_idle_full_post_iret_v5_runtime_evidence_line="$("${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh" \
        "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)"
    pit_after_idle_full_post_iret_v5_display_line="$("${repo_root}/scripts/xbox-display-capture-evidence-check.sh" \
        "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)"
    pit_after_idle_full_post_iret_v5_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)"
fi
pit_after_idle_full_post_iret_v5_iret_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v5_log}" ]; then
    pit_after_idle_full_post_iret_v5_iret_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_v5_loop_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v5_log}" ]; then
    pit_after_idle_full_post_iret_v5_loop_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_v5_flow_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_post_iret_v5_log}" ]; then
    pit_after_idle_full_post_iret_v5_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_post_iret_v5_log}" 2>&1 || true)")"
fi
pit_after_idle_full_pump_timeout_300s_raw_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-timeout-300s-v1.log"
pit_after_idle_full_pump_timeout_300s_combined_log="${real_dir}/browser-runtime-firefox-bidi-pit-after-idle-full-pump-timeout-300s-v1-combined.log"
pit_after_idle_full_pump_timeout_300s_log="${pit_after_idle_full_pump_timeout_300s_combined_log}"
if [ ! -f "${pit_after_idle_full_pump_timeout_300s_log}" ]; then
    pit_after_idle_full_pump_timeout_300s_log="${pit_after_idle_full_pump_timeout_300s_raw_log}"
fi
pit_after_idle_full_pump_timeout_300s_runtime_line="$(latest_line "${pit_after_idle_full_pump_timeout_300s_log}" '^BROWSER_RUNTIME_SMOKE ')"
pit_after_idle_full_pump_timeout_300s_runtime_evidence_line="not reported"
pit_after_idle_full_pump_timeout_300s_display_line="not reported"
pit_after_idle_full_pump_timeout_300s_dashboard_line="not reported"
pit_after_idle_full_pump_timeout_300s_section_map_line="not reported"
pit_after_idle_full_pump_timeout_300s_xbe_read_line="$(latest_line "${pit_after_idle_full_pump_timeout_300s_log}" '^BOOT_MARK b6 dashboard=xbe-read ')"
pit_after_idle_full_pump_timeout_300s_read_progress_line="$(latest_line "${pit_after_idle_full_pump_timeout_300s_log}" '^BOOT_MARK b6 dashboard=xbe-read-progress ')"
pit_after_idle_full_pump_timeout_300s_loaded_line="$(latest_line "${pit_after_idle_full_pump_timeout_300s_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
pit_after_idle_full_pump_timeout_300s_entry_ready_line="$(latest_line "${pit_after_idle_full_pump_timeout_300s_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .* status=ready ')"
if [ -f "${pit_after_idle_full_pump_timeout_300s_log}" ]; then
    pit_after_idle_full_pump_timeout_300s_runtime_evidence_line="$("${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh" \
        "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)"
    pit_after_idle_full_pump_timeout_300s_display_line="$("${repo_root}/scripts/xbox-display-capture-evidence-check.sh" \
        "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)"
    pit_after_idle_full_pump_timeout_300s_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)"
    pit_after_idle_full_pump_timeout_300s_section_map_line="$("${repo_root}/scripts/xbox-dashboard-section-map-evidence-check.sh" \
        "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)"
fi
pit_after_idle_full_pump_timeout_300s_iret_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_pump_timeout_300s_log}" ]; then
    pit_after_idle_full_pump_timeout_300s_iret_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)")"
fi
pit_after_idle_full_pump_timeout_300s_loop_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_pump_timeout_300s_log}" ]; then
    pit_after_idle_full_pump_timeout_300s_loop_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)")"
fi
pit_after_idle_full_pump_timeout_300s_flow_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_pump_timeout_300s_log}" ]; then
    pit_after_idle_full_pump_timeout_300s_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_pump_timeout_300s_log}" 2>&1 || true)")"
fi
preferred_b6_log="${real_b6_log}"
if [ -z "${preferred_b6_log}" ]; then
    preferred_b6_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v2-combined.log"
fi
if [ ! -f "${preferred_b6_log}" ] &&
   [ -f "${real_dir}/browser-runtime-firefox-bidi-section-map-v2.log" ]; then
    preferred_b6_log="${real_dir}/browser-runtime-firefox-bidi-section-map-v2.log"
fi
preferred_b6_runtime_line="$(latest_line "${preferred_b6_log}" '^BROWSER_RUNTIME_SMOKE ')"
preferred_b6_runtime_evidence_line="not reported"
preferred_b6_display_line="not reported"
preferred_b6_dashboard_line="not reported"
preferred_b6_section_map_line="not reported"
preferred_b6_xbe_read_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-read ')"
preferred_b6_read_progress_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-read-progress ')"
preferred_b6_loaded_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-loaded ')"
preferred_b6_entry_ready_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-entry-probe .* status=ready ')"
preferred_b6_section_map_marker_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-section-map .* phase=entry-ready ')"
if [ -z "${preferred_b6_section_map_marker_line}" ]; then
    preferred_b6_section_map_marker_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-section-map ')"
fi
preferred_b6_entry_section_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-section .* phase=entry-ready .* contains_entry=yes ')"
if [ -z "${preferred_b6_entry_section_line}" ]; then
    preferred_b6_entry_section_line="$(latest_line "${preferred_b6_log}" '^BOOT_MARK b6 dashboard=xbe-section .* contains_entry=yes ')"
fi
if [ -f "${preferred_b6_log}" ]; then
    preferred_b6_runtime_evidence_line="$("${repo_root}/scripts/xbox-browser-runtime-evidence-check.sh" \
        "${preferred_b6_log}" 2>&1 || true)"
    preferred_b6_display_line="$("${repo_root}/scripts/xbox-display-capture-evidence-check.sh" \
        "${preferred_b6_log}" 2>&1 || true)"
    preferred_b6_dashboard_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${preferred_b6_log}" 2>&1 || true)"
    preferred_b6_section_map_line="$("${repo_root}/scripts/xbox-dashboard-section-map-evidence-check.sh" \
        "${preferred_b6_log}" 2>&1 || true)"
fi
preferred_b6_iret_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${preferred_b6_log}" ]; then
    preferred_b6_iret_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${preferred_b6_log}" 2>&1 || true)")"
fi
preferred_b6_loop_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${preferred_b6_log}" ]; then
    preferred_b6_loop_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${preferred_b6_log}" 2>&1 || true)")"
fi
preferred_b6_flow_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${preferred_b6_log}" ]; then
    preferred_b6_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${preferred_b6_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_reference_iret_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_timer_pump_log}" ]; then
    pit_after_idle_full_post_iret_reference_iret_line="$(first_line "$("${repo_root}/scripts/xbox-iret-frame-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_timer_pump_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_reference_loop_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_timer_pump_log}" ]; then
    pit_after_idle_full_post_iret_reference_loop_line="$(first_line "$("${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_timer_pump_log}" 2>&1 || true)")"
fi
pit_after_idle_full_post_iret_reference_flow_line="not reported"
if [ -f "${native_post_iret_log}" ] && [ -f "${pit_after_idle_full_timer_pump_log}" ]; then
    pit_after_idle_full_post_iret_reference_flow_line="$(first_line "$("${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
        --native-log "${native_post_iret_log}" \
        --browser-log "${pit_after_idle_full_timer_pump_log}" 2>&1 || true)")"
fi
native_pfifo_idle_before_transition_log="${real_dir}/native-pfifo-activity-v1/boot-smoke.log"
pfifo_idle_before_transition_log="${real_dir}/browser-runtime-firefox-bidi-pfifo-activity-v1.log"
pfifo_idle_before_transition_compare_line="not reported"
if [ -f "${native_pfifo_idle_before_transition_log}" ] && [ -f "${pfifo_idle_before_transition_log}" ]; then
    pfifo_idle_before_transition_compare_line="$(first_line "$("${repo_root}/scripts/xbox-idle-before-pfifo-transition-compare.py" \
        --native-log "${native_pfifo_idle_before_transition_log}" \
        --browser-log "${pfifo_idle_before_transition_log}" 2>&1 || true)")"
fi
pfifo_idle_before_transition_runtime_line="$(latest_line "${pfifo_idle_before_transition_log}" '^BROWSER_RUNTIME_SMOKE ')"
native_kernel_loop_log_rel="$(repo_relative_path "${native_kernel_loop_log}")"
kernel_loop_log_rel="$(repo_relative_path "${kernel_loop_log}")"
kernel_loop_combined_log_rel="$(repo_relative_path "${kernel_loop_combined_log}")"
timer_pump_attribution_log_rel="$(repo_relative_path "${timer_pump_attribution_log}")"
pit_only_timer_pump_log_rel="$(repo_relative_path "${pit_only_timer_pump_log}")"
pit_after_idle_timer_pump_log_rel="$(repo_relative_path "${pit_after_idle_timer_pump_log}")"
pit_after_idle_full_timer_pump_log_rel="$(repo_relative_path "${pit_after_idle_full_timer_pump_log}")"
native_pfifo_boundary_log_rel="$(repo_relative_path "${native_pfifo_boundary_log}")"
pfifo_boundary_timer_pump_log_rel="$(repo_relative_path "${pfifo_boundary_timer_pump_log}")"
native_pfifo_transition_log_rel="$(repo_relative_path "${native_pfifo_transition_log}")"
pfifo_transition_timer_pump_log_rel="$(repo_relative_path "${pfifo_transition_timer_pump_log}")"
pfifo_transition_pit_at_transition_log_rel="$(repo_relative_path "${pfifo_transition_pit_at_transition_log}")"
pfifo_transition_gate_log_rel="$(repo_relative_path "${pfifo_transition_gate_log}")"
pfifo_transition_activity_log_rel="$(repo_relative_path "${pfifo_transition_activity_log}")"
pfifo_transition_defer_to_idle_log_rel="$(repo_relative_path "${pfifo_transition_defer_to_idle_log}")"
pfifo_transition_pre_commit_log_rel="$(repo_relative_path "${pfifo_transition_pre_commit_log}")"
native_post_iret_log_rel="$(repo_relative_path "${native_post_iret_log}")"
pit_after_idle_full_post_iret_v4_log_rel="$(repo_relative_path "${pit_after_idle_full_post_iret_v4_log}")"
pit_after_idle_full_post_iret_v5_raw_log_rel="$(repo_relative_path "${pit_after_idle_full_post_iret_v5_raw_log}")"
pit_after_idle_full_post_iret_v5_combined_log_rel="$(repo_relative_path "${pit_after_idle_full_post_iret_v5_combined_log}")"
pit_after_idle_full_post_iret_v5_log_rel="$(repo_relative_path "${pit_after_idle_full_post_iret_v5_log}")"
pit_after_idle_full_pump_timeout_300s_raw_log_rel="$(repo_relative_path "${pit_after_idle_full_pump_timeout_300s_raw_log}")"
pit_after_idle_full_pump_timeout_300s_combined_log_rel="$(repo_relative_path "${pit_after_idle_full_pump_timeout_300s_combined_log}")"
pit_after_idle_full_pump_timeout_300s_log_rel="$(repo_relative_path "${pit_after_idle_full_pump_timeout_300s_log}")"
preferred_b6_log_rel="$(repo_relative_path "${preferred_b6_log}")"
native_pfifo_idle_before_transition_log_rel="$(repo_relative_path "${native_pfifo_idle_before_transition_log}")"
pfifo_idle_before_transition_log_rel="$(repo_relative_path "${pfifo_idle_before_transition_log}")"
dashboard_loaded_line="not reported"
if [ -n "${real_b6_log}" ] && [ -f "${real_b6_log}" ]; then
    dashboard_loaded_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" "${real_b6_log}" 2>&1 || true)"
elif [ -n "${kernel_loop_combined_log}" ] && [ -f "${kernel_loop_combined_log}" ]; then
    dashboard_loaded_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" "${kernel_loop_combined_log}" 2>&1 || true)"
elif [ -n "${real_log}" ] && [ -f "${real_log}" ]; then
    dashboard_loaded_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" "${real_log}" 2>&1 || true)"
fi
native_reference_evidence_line="not reported"
if [ -n "${kernel_loop_combined_log}" ] && [ -f "${kernel_loop_combined_log}" ]; then
    native_reference_evidence_line="$("${repo_root}/scripts/xbox-native-reference-evidence-check.sh" "${kernel_loop_combined_log}" 2>&1 || true)"
elif [ -n "${real_log}" ] && [ -f "${real_log}" ]; then
    native_reference_evidence_line="$("${repo_root}/scripts/xbox-native-reference-evidence-check.sh" "${real_log}" 2>&1 || true)"
fi
dashboard_loaded_ide_poll_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-ide-poll-combined.log" ]; then
    dashboard_loaded_ide_poll_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-ide-poll-combined.log" 2>&1 || true)"
fi
dashboard_loaded_virtual_probe_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe-combined.log" ]; then
    dashboard_loaded_virtual_probe_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-virtual-probe-combined.log" 2>&1 || true)"
fi
dashboard_loaded_page_probe_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe-combined.log" ]; then
    dashboard_loaded_page_probe_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-page-probe-combined.log" 2>&1 || true)"
fi
dashboard_loaded_read_progress_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded-combined.log" ]; then
    dashboard_loaded_read_progress_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-read-progress-loaded-combined.log" 2>&1 || true)"
fi
dashboard_loaded_exec_probe_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context-combined.log" ]; then
    dashboard_loaded_exec_probe_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context-combined.log" 2>&1 || true)"
fi
dashboard_loaded_ret_target_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe-combined.log" ]; then
    dashboard_loaded_ret_target_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe-combined.log" 2>&1 || true)"
fi
dashboard_loaded_transition_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe-combined.log" ]; then
    dashboard_loaded_transition_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-transition-probe-combined.log" 2>&1 || true)"
fi
dashboard_loaded_edge_line="not reported"
if [ -f "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe-combined.log" ]; then
    dashboard_loaded_edge_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${real_dir}/browser-runtime-firefox-bidi-xbe-exec-edge-probe-combined.log" 2>&1 || true)"
fi
dashboard_loaded_branch_target_line="not reported"
if [ -f "${branch_target_combined_log}" ]; then
    dashboard_loaded_branch_target_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${branch_target_combined_log}" 2>&1 || true)"
fi
dashboard_loaded_entry_probe_line="not reported"
if [ -f "${entry_probe_combined_log}" ]; then
    dashboard_loaded_entry_probe_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${entry_probe_combined_log}" 2>&1 || true)"
fi
dashboard_loaded_entry_target_line="not reported"
if [ -f "${entry_target_combined_log}" ]; then
    dashboard_loaded_entry_target_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${entry_target_combined_log}" 2>&1 || true)"
fi
dashboard_loaded_dispatch_probe_line="not reported"
if [ -f "${dispatch_probe_combined_log}" ]; then
    dashboard_loaded_dispatch_probe_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${dispatch_probe_combined_log}" 2>&1 || true)"
fi
dashboard_loaded_kernel_loop_line="not reported"
if [ -f "${kernel_loop_combined_log}" ]; then
    dashboard_loaded_kernel_loop_line="$("${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" \
        "${kernel_loop_combined_log}" 2>&1 || true)"
fi
next_line="$(next_command_line)"
next_command="$(printf '%s\n' "${next_line}" | sed -n 's/.* command_json="\([^"]*\)".*/"\1"/p')"
next_reason="$(value_for "${next_line}" reason)"

cat >"${output}" <<EOF
# Xbox Browser Boot Status

Generated by \`scripts/xbox-boot-evidence-report.sh\`.

## Summary

| Field | Value |
| --- | --- |
| Overall result | ${summary_result} |
| Synthetic native milestone | ${synthetic_native} |
| Synthetic wasm milestone | ${synthetic_wasm} |
| Real B3 storage boot | ${real_b3} |
| Real B4 visible display | ${real_b4} |
| Real B5 browser usability | ${real_b5} |
| Next step | ${next_step} |

## Current Active Goal

The B3/B4/B5 browser boot goal is complete when the summary above is
\`complete\`. The active long-term goal is B6: prove the Xbox dashboard is
loaded, not merely that real storage and non-empty display frames are present.

The B6 objective is to add reliable dashboard/XBE read-load-execute markers,
capture native reference frames, use Playwright-preferred browser visual
capture with Firefox BiDi fallback, compare browser frames to native
references, and keep an auditable B6 checker that rejects B4-only evidence.

B6 should require explicit dashboard/XBE evidence plus visual reference
evidence:

- \`BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...\`
- \`BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime ... source=virtual-header ...\`
- \`BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_code_read=yes phys_match=yes ...\`
- \`BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime ...\`
- \`NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...\`
- \`BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes ...\`

Use Playwright as the preferred browser automation path for screenshot/canvas
capture. On this machine Playwright is installed globally, so run browser tests
with:

\`\`\`sh
hash -r
export PATH="\$HOME/.npm-global/bin:\$PATH"
export NODE_PATH="\$(npm root -g)"
node -e 'require("playwright"); console.log("playwright ok")'
\`\`\`

If the npm-global PATH was added to a shell startup file after the current
terminal opened, run \`source ~/.profile\` or open a fresh shell before using
the shorter interactive commands. The current local sanity check was verified
on 2026-06-28 with the explicit unattended env prefix below: Node \`v22.22.2\`,
npm \`10.9.7\`, global Playwright \`1.61.1\`, and browser binaries under
\`\$HOME/.cache/ms-playwright\`.

Other verified local tools: Firefox \`140.11.0esr\`, Python \`3.12.13\`,
\`qemu-img\` \`10.1.0\`, and Podman \`5.8.2\` through
\`/tmp/xemu-podman-wrapper/docker\`.

Browser dashboard visual comparison is wired through
\`XEMU_BROWSER_DASHBOARD_NATIVE_HASH=<native-frame-hash>\` in
\`scripts/xbox-browser-runtime-smoke.sh\`. Both the Playwright path and Firefox
BiDi fallback emit \`BROWSER_DASHBOARD_CAPTURE\` from the latest non-empty
browser display capture only when a native hash is supplied; by default
\`XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED=1\` keeps that evidence at
\`result=skip reason=missing-xbe-executed\` until true browser-runtime
\`dashboard=xbe-executed\` exists.

The native synthetic matrix may need the local Podman-backed Docker wrapper:

\`\`\`sh
export PATH="/tmp/xemu-podman-wrapper:\$PATH"
\`\`\`

Keep the Firefox BiDi scripts as fallback when Playwright is unavailable, and
prefer that path for current long real browser-runtime probes until Playwright
reaches comparable B4/IDE-read evidence. For unattended commands, use explicit
environment prefixes:

\`\`\`sh
PATH=/tmp/xemu-podman-wrapper:\$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \\
NODE_PATH=\$HOME/.npm-global/lib/node_modules \\
<command>
\`\`\`

Current local fixture exports for this machine:

\`\`\`sh
export XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin'
export XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin'
export XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin
export XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2'
\`\`\`

The user-supplied EEPROM source is
\`/home/sammy/.local/share/xemu/xemu/eeprom.bin\`; current B6 smoke commands use
the \`/tmp/xemu-b6-eeprom.bin\` copy to keep unattended runs isolated.

To force the current real matrix through the Firefox BiDi browser-runtime path,
run it with:

\`\`\`sh
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi scripts/xbox-real-b3-matrix.sh
\`\`\`

The current B6 contract checker is:

\`\`\`sh
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log
\`\`\`

It is expected to fail until browser-runtime dashboard/XBE read/load/entry-ready/execute
evidence and native reference-frame comparison are implemented. The generic XBE
load/execute marker probe is present, and native-headless FATX/XBE read
correlation can prove the HDD contains/read-serves \`xboxdash.xbe\`, but B6 still
requires browser-runtime context plus browser-vs-native visual proof. The
optional physical RAM scan emits \`dashboard=xbe-header-resident
source=physical-scan\` as a diagnostic only; it must not satisfy
\`dashboard=xbe-loaded\`. The entry-ready probe proves the decoded entry page is
readable and physically matched, but it must not satisfy
\`dashboard=xbe-executed\`. Use the checker selftest when changing the contract:

\`\`\`sh
scripts/xbox-dashboard-loaded-evidence-check-selftest.sh
\`\`\`

To diagnose the read side separately, run:

\`\`\`sh
scripts/xbox-dashboard-xbe-read-evidence.py --hdd "\$XEMU_HDD" --log build-real-b3-matrix/real-b3-matrix.log
scripts/xbox-dashboard-xbe-read-evidence.py --hdd "\$XEMU_HDD" --log build-real-b3-matrix/real-b3-matrix.log --require-context browser-runtime
\`\`\`

The first command may pass with \`context=native-headless\`; that is useful
native evidence but does not satisfy B6. The second command must pass before
B6 can claim browser-runtime dashboard XBE read evidence in the standard matrix
log. The current diagnostic Firefox BiDi IDE-poll artifact already proves that
read side separately.

Current B6 progress: Firefox BiDi with the browser IDE AIO poll fix now reaches
browser-runtime dashboard storage reads. The standard real matrix log and the
combined Firefox BiDi IDE-poll diagnostic contain
\`BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...\` for
\`xboxdash.xbe\`. Focused native and Firefox BiDi browser-runtime diagnostics
emit \`dashboard=xbe-dma-buffer\` plus
\`dashboard=xbe-virtual-probe\`, proving the dashboard header reached guest IDE
DMA memory while the XBE image base \`0x00010000\` was still unmapped. The
page-probe runs narrowed that to \`page_status=pde-not-present\` with
\`cr3=0x0000f000\` and \`pde=0\` for the dashboard image base at the first
dashboard sector. The newer read-progress run shows the mapping appears on the
next dashboard read and now emits
\`BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime ... source=virtual-header\`.
The TCG translated-block execution hook now builds in both native and browser
targets. The execution detector checks direct dashboard image PCs and high-bit
aliases only when the observed PC and the low dashboard image alias translate to
the same guest physical page. The verbose TCG execution diagnostic budgets are
now reserved until \`dashboard=xbe-entry-probe status=ready\`, while
\`dashboard=xbe-executed\` detection itself remains active immediately after
\`dashboard=xbe-loaded\`. Post-entry diagnostics include \`entry_ready=yes\`.
The latest native and Firefox BiDi browser-runtime
diagnostics add phys-map plus CPU context fields to
\`dashboard=xbe-exec-probe\`: \`address_mode\`, \`guest_phys\`,
\`image_phys\`, \`phys_match\`, \`cpu_mode\`, \`cpl\`, \`cs\`, \`ss\`,
registers, and control registers. The latest ret-target diagnostics also log a
bounded code-site hash, first opcode/modrm fields, branch kind, and readable
return/direct/register branch targets without dumping raw code bytes. Native
ret samples return to \`0x80030e84\`; browser ret samples return to kernel high
aliases such as \`0x8001ae75\` and \`0x8001a429\`. Those targets are still
\`branch_relation=above\` with no physical match to the loaded dashboard image.
The post-TB transition diagnostics now sample the synchronized CPU PC after
each translated block and can mark execution if that next PC reaches the loaded
image. Native transitions still cycle through kernel PCs such as
\`0x80030e84\`, \`0x80014f32\`, and \`0x800426d4\`; browser transitions still
cycle through kernel PCs such as \`0x8002430e\`, \`0x8001ae75\`,
\`0x80060ffe\`, and \`0x80014fb4\`. No post-TB next PC physically matches the
loaded dashboard image. The latest transition-edge diagnostics add bounded
\`dashboard=xbe-exec-edge\` summaries, controlled by
\`XEMU_BOOT_TRACE_XBE_EXEC_EDGE_LIMIT\`, so repeated post-load kernel edges can
be seen without flooding logs. Current native and browser edge samples still
cycle through kernel/high-alias PCs and do not emit \`dashboard=xbe-executed\`.
The latest branch-target diagnostics widen the retained edge cache to 64
unique edge shapes and decode register plus memory-indirect \`FF /2\` and
\`FF /4\` call/jmp operands in edge samples. Native and browser wide-edge
artifacts both resolve a memory-indirect \`call-mem32\` through operand address
\`0x8003ad24\` to target \`0x800241fe\`; the browser wide-edge run also records
\`call-reg\` dispatch to \`0x80046280\`. The newer branch-target classification
artifact adds \`next_branch_relation\`, \`next_branch_address_mode\`, physical
mapping fields, and \`next_branch_phys_match\` to transition and edge logs.
Those fields prove the sampled indirect targets remain kernel/high-alias paths,
not dashboard XBE execution.
The latest alias-compare diagnostic adds bounded
\`dashboard=xbe-alias-compare\` markers, controlled by
\`XEMU_BOOT_TRACE_XBE_ALIAS_COMPARE_LIMIT\`, for high-bit PCs that numerically
overlap the dashboard XBE virtual range. It hashes the executing high-alias
code and the corresponding loaded XBE image bytes without dumping raw code.
The current browser artifact,
\`build-real-b3-matrix/browser-runtime-firefox-bidi-alias-compare-combined.log\`,
passes B4 display capture, B5 runtime evidence, and browser-runtime
\`xboxdash.xbe\` read correlation, but still fails the B6 checker at
\`missing-xbe-executed-marker\`. Its alias-compare markers show
\`phys_match=no\` and \`code_hash_match=no\`, proving the sampled high-alias
overlaps are kernel-code paths rather than dashboard bytes executed through a
different alias. The hash audit helper also compares sampled
\`dashboard=xbe-exec-probe\`, \`dashboard=xbe-exec-transition\`, and
\`dashboard=xbe-exec-edge\` code hashes against the dashboard file; current
callback-v1 and icount shift=0 artifacts report \`exec_disk_hash_match=0\`, so
sampled execution streams still do not match \`xboxdash.xbe\` bytes.
The native physical-compare diagnostic adds bounded
\`dashboard=xbe-phys-compare\` markers, controlled by
\`XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT\`, after the decoded entry page is
ready. It scans the loaded XBE virtual image mappings for the executing TB's
guest physical address and hashes both sides when a physical match exists. The
current native 20s artifact records
\`${native_phys_compare_no_match_count:-0}\` no-match samples out of
\`${native_phys_compare_count:-0}\` physical-compare samples and no
\`result=match\`. The browser Firefox BiDi physical-compare artifact records
\`${browser_phys_compare_no_match_count:-0}\` no-match samples out of
\`${browser_phys_compare_count:-0}\` samples before its wrapper timeout, also
with no \`result=match\`. These sampled post-entry execution streams still stay
in kernel physical pages rather than the loaded dashboard image bytes.
The target-hash-v1 entry-target diagnostic also hashes decoded branch target
bytes and the corresponding low XBE image bytes as \`target_code_hash\` and
\`target_image_code_hash\`; the same helper reports \`target_disk_hash_match\`
without dumping proprietary bytes.
The latest entry-point diagnostics prove the decoded dashboard entry becomes
readable in both native and browser-runtime contexts. Native
\`build-real-b3-matrix/native-60s-xbe-entry-probe-v2/boot-smoke.log\` and
browser
\`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-probe-combined.log\`
both probe decoded dashboard entry \`0x00017d60\`; each first reports
\`dashboard=xbe-entry-probe ... status=unreadable\` and then one \`status=ready\`
marker with \`entry_phys=0x000c7d60\`,
\`entry_code_hash=0x7cbb4e8a328f1553\`, and \`entry_opcode=0x55\`. The browser
artifact passes B4 display capture, B5 runtime evidence, and browser-runtime
\`xboxdash.xbe\` read correlation, but the combined log still fails the B6
checker at \`missing-xbe-executed-marker\`. Entry readiness narrows the handoff
window, but it is still diagnostic only.
The latest entry-target diagnostics add bounded
\`dashboard=xbe-entry-target-probe\` markers when decoded branch targets fall
within a configurable window around the dashboard entry point. Native
\`build-real-b3-matrix/native-60s-xbe-entry-target-probe/boot-smoke.log\` and
browser
\`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-target-probe-combined.log\`
both emit 16 entry-target probes. The browser artifact passes B4 display
capture, B5 runtime evidence, and browser-runtime \`xboxdash.xbe\` read
correlation, but the combined log still fails the B6 checker at
\`missing-xbe-executed-marker\`. The sampled near-entry targets are still
kernel/high-alias paths with \`target_status=near-phys-unknown\`, such as
ret-stack targets near \`0x8001ae75\` and call targets near \`0x80018d30\` or
\`0x800241fe\`; none prove dispatch into the loaded dashboard image. The
target-hash-v1 artifact includes target and low-image code hashes on these
markers so the hash audit helper can distinguish decoded handoff candidates
from kernel/high-alias targets.
The latest dispatch diagnostics inspect post-load register and top-stack
candidates without dumping raw stack contents. Native
\`build-real-b3-matrix/native-60s-xbe-dispatch-probe-v3/boot-smoke.log\` emits
16 \`dashboard=xbe-dispatch-probe\` markers, and browser
\`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3-combined.log\`
emits 10. Both keep \`reg_phys_match_count=0\` and
\`reg_entry_near_count=0\`; the browser probes keep
\`reg_first_candidate=none\` throughout. The only native register candidate is
a high-alias mismatch (\`ecx=0x8003a950\`) above the dashboard image, not an
execution handoff. Stack direct matches, when present, point into XBE headers
(\`stack_first_in_headers=yes\`); other stack candidates are high-alias
mismatches or unknown physical mappings near kernel paths such as
\`0x8001ae75\`, \`0x8001a429\`, and \`0x800141bb\`. The browser artifact
passes B4 display capture, B5 runtime evidence, and browser-runtime
\`xboxdash.xbe\` read correlation, but still fails the B6 checker at
\`missing-xbe-executed-marker\`.
The latest PFIFO/NV2A diagnostics add bounded \`pfifo=progress\` markers
controlled by \`XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT\`, divergence-window
\`pfifo=window\` markers controlled by
\`XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_START\` and
\`XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_LIMIT\`, bounded \`pgraph=method\` markers
controlled by \`XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_LIMIT\`, divergence-window
\`pgraph=method-window\` markers controlled by
\`XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_START\` and
\`XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_LIMIT\`, bounded
\`pgraph=notify-error\` markers controlled by
\`XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT\`, bounded \`pgraph=notify-clear\`
markers controlled by \`XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT\`,
filtered \`nv2a=irq-source\` markers, bounded \`nv2a=irq-line\` markers
controlled by \`XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT\`, a separate non-priority
IRQ-line cap controlled by
\`XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT\`, and a diagnostic-only
NV2A wait-state snapshot on each \`dashboard=kernel-loop-probe\`. Native
\`${native_kernel_loop_log_rel}\` and browser
\`${kernel_loop_combined_log_rel}\`
still show post-load execution remains in kernel/high-alias paths.
Native emitted ${native_pfifo_count} PFIFO progress markers,
${native_pfifo_puller_method_count} \`puller-method\` markers,
${native_pfifo_window_count} PFIFO window markers,
${native_pgraph_method_count} PGRAPH method markers,
${native_pgraph_method_window_count} PGRAPH method-window markers, and
${native_pgraph_notify_count} PGRAPH notify-error markers plus
${native_pgraph_notify_clear_count} PGRAPH notify-clear markers; browser emitted
${dashboard_pfifo_firefox_bidi_count} PFIFO progress markers,
${dashboard_pfifo_firefox_bidi_puller_method_count} \`puller-method\` markers,
${dashboard_pfifo_window_firefox_bidi_count} PFIFO window markers,
${dashboard_pgraph_method_firefox_bidi_count} PGRAPH method markers,
${dashboard_pgraph_method_window_firefox_bidi_count} PGRAPH method-window
markers, and
${dashboard_pgraph_notify_firefox_bidi_count} PGRAPH notify-error markers plus
${dashboard_pgraph_notify_clear_firefox_bidi_count} PGRAPH notify-clear
markers. This fixed the stale aggregate PGRAPH interrupt state after PGRAPH
interrupt clears, but it did not prove dashboard execution. Native and browser
both show PGRAPH pending clearing from \`0x00100000\` to \`0x00000000\` with
\`waiting_nop_before=yes\` and \`waiting_nop_after=no\`. The null-renderer
flip-stall mismatch is fixed: native and browser both continue past
\`NV097_FLIP_STALL\`, consume the late command window through
\`NV097_SET_COLOR_CLEAR_VALUE\`, and reach PFIFO empty with
\`dma_get=dma_put=0x03881318\` and \`waiting_flip=no\`. The remaining comparator
divergence is post-command CPU/kernel-loop behavior, not PFIFO/PGRAPH command
progress.
The current command-stream comparator reports:
\`${pgraph_command_stream_compare_line}\`.
The current post-command CPU/XBE handoff comparator reports:
\`${post_command_handoff_compare_line}\`.
The current post-command kernel-loop cluster report is:
\`${post_command_loop_clusters_line}\`.
The current post-command NV2A IRQ/PMC state comparator reports:
\`${post_command_irq_state_compare_line}\`.
The current PCRTC vblank divergence comparator reports:
\`${pcrtc_vblank_divergence_line}\`.
The current interrupt-return frame comparator reports:
\`${iret_frame_compare_line}\`.
The current post-idle interrupt-flow comparator reports:
\`${post_idle_interrupt_flow_compare_line}\`.
The current TCG timer-pump attribution comparator uses
\`${timer_pump_attribution_log_rel}\` and reports:
\`${timer_pump_attribution_compare_line}\`.
The cluster report preserves all loop samples, but its \`after_idle_*\` fields
are the authoritative post-command CPU sample set. If
\`after_idle_divergence=browser-no-after-idle-loop-samples\`, the browser log
has reached PFIFO empty but has not yet sampled CPU/kernel-loop state after
that point. If \`after_idle_divergence=edge-mismatch\`, both native and browser
sampled after PFIFO empty, but their post-command kernel edges differ. The IRQ
state comparator preserves whether that edge mismatch coincides with divergent
NV2A PMC/PCRTC state. The post-idle interrupt-flow comparator is the focused
CPU-flow boundary: it compares the post-PFIFO-idle service vectors, IRET
returns, and first post-service kernel-loop edges without treating any of those
diagnostics as B6 completion. The current PIC-ack serviceable idle-loop
diagnostic leaves native and browser with the same PCRTC-vblank shape: no vblank
raises, matching first-enable pending state, and matching loop PMC
pending/enabled state after stream idle. The opt-in browser TCG timer pump is controlled by
\`XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL\` plus
\`XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE\`. With interval \`1\` and mode
\`idle-loop-serviceable\`, the browser only treats the native-observed
serviceable idle PC \`0x8001b030\` as timer-pump eligible. This removes the older
first-IRQ-at-\`0x8001b02f\` boundary: the browser first hard IRQ is now set at
\`0x8001b030\` with interrupts enabled and no IRQ inhibition. The current
browser artifact accepts vector \`0x30\`, enters the same handler PC as native,
\`0x80030e4c\`, and the sampled service frame matches native at the first
handler entry. The latest watched IRQ markers show the extra browser vectors
are sourced before acknowledgement: guest IRQ 12 is asserted by the Xbox LPC
ACPI PM route (\`source=pm route_type=acpi pic_irq=12\`) and guest IRQ 6 is
asserted by \`source=mcpx-aci route_type=internal pic_irq=6\`, both at
\`eip=0x8001b030\` after PFIFO reaches pusher-empty. The corresponding PIC
line markers show \`guest_irq=12\` on the slave IRQ4 line and \`guest_irq=6\`
on the master IRQ6 line. The current source-level markers add
\`browser_pm_sci_events=2\` with \`browser_first_pm_sci_assert=pm:pm1-update:assert\`
and \`browser_ac97_irq_events=2\` with \`browser_first_ac97_irq_assert=ac97:bm=1:assert\`.
The current callback, arming, and completion markers for this same boundary are
\`xbox-pm=tmr-callback\` for PM timer callback firing, \`ac97=callback\` for
AC97 playback callback entry, \`xbox-pm=evt-write\` for PM1 status/enable
writes, \`ac97=bm-write\` for AC97 bus-master BDBAR/LVI/CR/SR writes, and
\`ac97=transfer\` for descriptor-completion transfer state. The comparator's
\`*_pm_timer_*\`, \`*_ac97_callback_*\`, \`*_pm_evt_write_*\`,
\`*_ac97_bm_write_*\`, and \`*_ac97_transfer_*\` fields are the preferred way
to distinguish callback firing, divergent guest programming, descriptor
completion, or host timing. These markers are diagnostic-only and must not
satisfy B6 without browser-runtime \`dashboard=xbe-executed\` plus native-frame
visual match evidence.
The timer-pump attribution artifact is diagnostic-only because it times out and
does not itself carry the full B6 read evidence, but it proves the source of the
remaining browser-only PM/AC97 assertions: the comparator reports
\`browser_pm_timer_pump_active_events=1\`,
\`browser_ac97_callback_pump_active_events=9\`,
\`browser_ac97_transfer_pump_active_events=1\`, and
\`browser_ac97_irq_pump_active_events=1\`, while cleanup writes such as
\`browser_pm_evt_write_pump_active_events\` and
\`browser_ac97_bm_write_pump_active_events\` remain zero. That means the next
technical slice is to make the browser timer-pump behavior match the native
main-loop timer boundary, or filter the diagnostic pump so it does not run
unrelated PM timer and AC97 playback callbacks while trying to deliver the
native PIT service point.
The PIT-only timer-pump artifact uses
\`${pit_only_timer_pump_log_rel}\` and reports:
\`${pit_only_timer_pump_compare_line}\`.
That diagnostic filters the browser TCG pump to the tagged PIT timer. It still
times out and does not itself carry the full combined B6 read evidence, so it
does not satisfy B6, but it removes the previous PM/AC97 interrupt noise:
\`browser_extra_vectors=none\`, \`browser_extra_pic_ack_vectors=none\`,
\`browser_extra_pic_line_assert_irqs=none\`,
\`browser_extra_lpc_route_assert_irqs=none\`, \`browser_pm_timer_events=0\`,
\`browser_ac97_callback_events=0\`, \`browser_pm_sci_events=0\`,
\`browser_ac97_transfer_events=0\`, and \`browser_ac97_irq_events=0\`. The first
service frame and first IRET now match native, leaving the current boundary as
a CPU-flow mismatch after the native-matching PIT/vector \`0x30\` service rather
than a PM timer or AC97 callback divergence.
The post-idle PIT gate artifacts use
\`${pit_after_idle_timer_pump_log_rel}\` and
\`${pit_after_idle_full_timer_pump_log_rel}\`. The first waits for a small
post-PFIFO idle-loop sample before allowing the PIT-only pump, and the second
waits for the full \`XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT\` sample
budget. They report:
\`${pit_after_idle_timer_pump_compare_line}\`
and
\`${pit_after_idle_full_timer_pump_compare_line}\`.
Both remain diagnostic-only because the runtime still times out without
\`dashboard=xbe-executed\`. The full-idle run is the sharper artifact: PM/AC97
noise remains absent, first service and first IRET still match native, and the
earlier browser-only first post-service loop disappears
(\`browser_first_post_service_loop=none\`). The remaining mismatch is earlier:
the browser's first stream-idle loop sample starts at
\`0x8001b02f -> 0x8001b030\`, while native starts at
\`0x8001b030 -> 0x8001b02f\`. Treat the next B6 boundary as PFIFO stream-idle
snapshot timing versus CPU idle-loop phase, not as a PM timer, AC97 callback,
or repeated PIT-delivery issue.
The PFIFO stream-idle boundary artifacts use
\`${native_pfifo_boundary_log_rel}\` and
\`${pfifo_boundary_timer_pump_log_rel}\`. They report:
\`${pfifo_stream_idle_boundary_compare_line}\`.
This is the sharper current diagnostic. Native and wasm builds passed with the
new marker, and the fresh browser runtime still times out without
\`dashboard=xbe-executed\`, but the first true PFIFO-empty boundary is now
different before repeated PIT tuning matters: native is at \`eip=0x80042910\`
with last transition \`0x800426de -> 0x80042910\`, while browser is already at
\`eip=0x8001b030\` with last transition \`0x8001b030 -> 0x8001b02f\`. Treat the
next B6 boundary as PFIFO pusher scheduling or CPU/PFIFO ordering at
\`pusher-empty\`, not as another generic timer-pump mode.
The PFIFO stream-idle transition artifacts use
\`${native_pfifo_transition_log_rel}\` and
\`${pfifo_transition_timer_pump_log_rel}\`. They report:
\`${pfifo_stream_idle_transition_compare_line}\`.
The focused IRQ/timer timing report is:
\`${pfifo_transition_irq_timing_line}\`.
This is now the sharpest local B6 split point. Native and wasm builds passed,
and both fresh probes emit the new marker. At the exact final \`DMA_GET\`
commit from \`0x03881314\` to \`0x03881318\`, native and browser commit the
same PFIFO command but disagree on pending hard-IRQ state. Native reaches the
transition with \`cpu_interrupt_request=0x00000002\`; browser reaches the same
transition with \`cpu_interrupt_request=0x00000000\`. Treat the next B6
boundary as CPU scheduling or IRQ-delivery timing relative to the final PFIFO
pusher update, not as a later idle-loop, repeated PIT, or renderer issue.
The PFIFO-transition PIT-at-transition artifact uses
\`${pfifo_transition_pit_at_transition_log_rel}\`. It reports:
\`${pfifo_transition_pit_at_transition_compare_line}\`
and
\`${pfifo_transition_pit_at_transition_flow_line}\`.
This diagnostic proves the focused mode fires only after the exact
\`pfifo=stream-idle-transition\` marker and removes the PM/AC97 noise and extra
vectors, but it still does not prove B6. Compared against the fresh native
activity run, the core mismatch remains: native already has
\`CPU_INTERRUPT_HARD\` pending at the transition, while browser reaches the
transition with no pending hard IRQ and sets it later from the TCG-side timer
pump. Treat the next slice as IRQ/timer scheduling at the final PFIFO
transition, not later PIT pump timing.
The pre-transition gate diagnostics use
\`${pfifo_transition_gate_log_rel}\` and
\`${pfifo_transition_activity_log_rel}\`. The gate-only run reports:
\`${pfifo_transition_gate_line}\`
and
\`${pfifo_transition_gate_compare_line}\`.
That proves the idle-PC-only pre-transition gate can miss the final command
window when the browser reaches the near-final PFIFO activity while the CPU is
still at \`0x800426de\`. The activity-gated PIT-only run reports:
\`${pfifo_transition_activity_gate_line}\`
and
\`${pfifo_transition_activity_timer_line}\`.
Its comparator reports:
\`${pfifo_transition_activity_compare_line}\`
and the post-idle flow report is:
\`${pfifo_transition_activity_flow_line}\`.
This is diagnostic-only and still fails B6. It proves the PIT-only pump can set
\`CPU_INTERRUPT_HARD\` before PFIFO empties, but doing it at
\`puller-method-pgraph-call\` is too early: the browser CPU accepts vector
\`0x30\` and reaches handler PC \`0x80030e4c\` before the final
\`pfifo=stream-idle-transition\` marker. The remaining slice is therefore a
scheduling/order problem: make the browser observe the native ordering where
the IRQ is pending at the final PFIFO commit and serviced after it, not before
it and not later from a post-transition pump.
The focused defer-to-idle artifact uses
\`${pfifo_transition_defer_to_idle_log_rel}\`. Its runtime line is:
\`${pfifo_transition_defer_to_idle_runtime_line}\`.
Its B6 checker result is:
\`${pfifo_transition_defer_to_idle_dashboard_line}\`.
Its transition IRQ timing report is:
\`${pfifo_transition_defer_to_idle_irq_timing_line}\`.
Its post-idle interrupt-flow report is:
\`${pfifo_transition_defer_to_idle_flow_line}\`.
This run is still diagnostic-only and does not satisfy B6, but it proves one
important ordering improvement: the browser can keep the PIT hard IRQ pending
through the post-PFIFO handoff and service vector \`0x30\` at the native
serviceable idle PC \`0x8001b030\`. The first browser hard-IRQ service and IRET
now use the same return frame hash as native. The remaining mismatch is earlier:
native already has \`CPU_INTERRUPT_HARD\` pending at the final PFIFO transition,
while browser still sets it after that transition from the TCG-side PIT pump.
The PFIFO pre-commit PIT artifact uses
\`${pfifo_transition_pre_commit_log_rel}\`. Its runtime line is:
\`${pfifo_transition_pre_commit_runtime_line}\`.
Its B6 checker result is:
\`${pfifo_transition_pre_commit_dashboard_line}\`.
Its pre-commit marker is:
\`${pfifo_transition_pre_commit_marker_line}\`.
Its transition IRQ timing report is:
\`${pfifo_transition_pre_commit_irq_timing_line}\`.
Its post-idle interrupt-flow report is:
\`${pfifo_transition_pre_commit_flow_line}\`.
This run is still diagnostic-only and times out without
\`dashboard=xbe-executed\`, but it moves the boundary forward: browser now has
\`CPU_INTERRUPT_HARD=0x00000002\` pending at the final
\`pfifo=stream-idle-transition\`, and the first vector \`0x30\` service/IRET
frame still matches native. The remaining mismatch is after the first service:
browser records a post-service loop edge
\`0x80030e4c -> 0x80014f2d\`, while native's compact reference flow proceeds
through the IRET marker first and continues servicing repeated PIT vector
\`0x30\` events. The next slice is post-interrupt return/loop flow after the
first matching \`0x30\` service, not the older pending-IRQ-at-transition gap.
The fresh native post-IRET flow reference is \`${native_post_iret_log_rel}\`.
Its summary is:
\`${native_post_iret_summary_line:-not reported}\`.
Its metric line is:
\`${native_post_iret_metric_line:-not reported}\`.
Compared against the useful browser
\`${pit_after_idle_full_timer_pump_log_rel}\` artifact, the interrupt-return
frame comparator reports:
\`${pit_after_idle_full_post_iret_reference_iret_line}\`.
The post-command loop-cluster comparator reports:
\`${pit_after_idle_full_post_iret_reference_loop_line}\`.
The post-idle interrupt-flow comparator reports:
\`${pit_after_idle_full_post_iret_reference_flow_line}\`.
This is the current non-looping B6 diagnosis: the useful browser artifact
matches the native preferred vector \`0x30\` service/IRET return frame and has
the same after-idle top loop edge, but browser still lacks matching after-idle
CPU interrupt samples and still emits no \`dashboard=xbe-executed\`.
The follow-up v4 browser run,
\`${pit_after_idle_full_post_iret_v4_log_rel}\`, is a negative diagnostic. Its
runtime line is:
\`${pit_after_idle_full_post_iret_v4_runtime_line:-not reported}\`.
Its B6 checker result is:
\`${pit_after_idle_full_post_iret_v4_dashboard_line}\`.
Its comparison lines are:
\`${pit_after_idle_full_post_iret_v4_iret_line}\`
\`${pit_after_idle_full_post_iret_v4_loop_line}\`
\`${pit_after_idle_full_post_iret_v4_flow_line}\`.
V4 passes the browser runtime evidence again but does not reach PFIFO
stream-idle; it re-samples an earlier PGRAPH interrupt-enable wait. Do not use
v4 as the preferred PFIFO-empty browser reference and do not repeat that same
larger early kernel-loop sampling experiment unless the trace-control behavior
is changed.
The follow-up v5 browser run uses raw runtime log
\`${pit_after_idle_full_post_iret_v5_raw_log_rel}\`; when available, the status
prefers combined log \`${pit_after_idle_full_post_iret_v5_combined_log_rel}\`,
which appends FATX/IDE read evidence from
\`scripts/xbox-combine-dashboard-xbe-read-evidence.sh\`. This v5 run decouples
the after-idle PIT pump gate from the after-idle kernel-loop sample budget with
\`XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=16\`. Its runtime line is:
\`${pit_after_idle_full_post_iret_v5_runtime_line:-not reported}\`.
Its browser runtime evidence is:
\`${pit_after_idle_full_post_iret_v5_runtime_evidence_line}\`.
Its B4 display capture evidence is:
\`${pit_after_idle_full_post_iret_v5_display_line}\`.
Its B6 checker result is:
\`${pit_after_idle_full_post_iret_v5_dashboard_line}\`.
Its latest dashboard read/load/entry markers are:
\`${pit_after_idle_full_post_iret_v5_read_progress_line:-not reported}\`
\`${pit_after_idle_full_post_iret_v5_read_complete_line:-not reported}\`
\`${pit_after_idle_full_post_iret_v5_loaded_line:-not reported}\`
\`${pit_after_idle_full_post_iret_v5_entry_ready_line:-not reported}\`.
Its comparison lines are:
\`${pit_after_idle_full_post_iret_v5_iret_line}\`
\`${pit_after_idle_full_post_iret_v5_loop_line}\`
\`${pit_after_idle_full_post_iret_v5_flow_line}\`.
V5 is forward progress over v4 because it proves B4/B5 again plus
browser-runtime dashboard XBE read correlation, \`dashboard=xbe-loaded\`, and
\`dashboard=xbe-entry-probe status=ready\`. The raw C read-progress marker uses
XBE header \`image_size\`, which is the in-memory image size, not the FATX file
length; the FATX correlator reports the actual \`xboxdash.xbe\` file size as
the same byte count already read by native and browser. It still does not prove
B6: there is no accepted \`dashboard=xbe-executed\`, no browser PFIFO
stream-idle in this v5 artifact, and no native visual-reference match. If the
combined artifact is missing, the raw log will intentionally fail at
\`missing-xbe-read-complete-marker\`; generate the combined artifact before
treating the read side as the active blocker.
The current preferred B6 browser artifact is the summary-selected log
\`${preferred_b6_log_rel}\`. The newest section-map run uses rebuilt wasm and,
when the combined artifact is selected, appends FATX/IDE dashboard-read proof.
Its runtime line is:
\`${preferred_b6_runtime_line:-not reported}\`.
Its browser runtime evidence is:
\`${preferred_b6_runtime_evidence_line}\`.
Its B4 display capture evidence is:
\`${preferred_b6_display_line}\`.
Its B6 checker result is:
\`${preferred_b6_dashboard_line}\`.
Its XBE section-map diagnostic result is:
\`${preferred_b6_section_map_line}\`.
Its latest dashboard read/load/entry markers are:
\`${preferred_b6_xbe_read_line:-not reported}\`
\`${preferred_b6_read_progress_line:-not reported}\`
\`${preferred_b6_loaded_line:-not reported}\`
\`${preferred_b6_entry_ready_line:-not reported}\`.
Its latest section-map markers are:
\`${preferred_b6_section_map_marker_line:-not reported}\`
\`${preferred_b6_entry_section_line:-not reported}\`.
Its comparison lines are:
\`${preferred_b6_iret_line}\`
\`${preferred_b6_loop_line}\`
\`${preferred_b6_flow_line}\`.
This supersedes the earlier 300s and v5 combined logs as the front-most browser
evidence: it is B5-pass, display-pass, dashboard-read combined when the combined
log is present, has an entry-ready XBE section map, and matches the native
preferred vector \`0x30\` service/IRET frame. It still does not complete B6
because the checker correctly fails at \`missing-xbe-executed-marker\`;
native-reference dashboard capture and browser-vs-native visual match must wait
for true browser-runtime \`dashboard=xbe-executed\`. The older 300s combined log
remains a historical PFIFO-empty/timer reference, but it no longer owns the
current next step. The section map is diagnostic-only and must not satisfy B6
without \`dashboard=xbe-executed\`.
The \`dashboard=xbe-executed\` marker is intentionally strict: it must carry
\`phys_match=yes\` and executable section metadata (\`section_flags\` containing
\`0x4\`), and \`scripts/xbox-dashboard-loaded-evidence-check.sh\` rejects weaker
executed markers.
The idle-before-PFIFO-transition artifacts use
\`${native_pfifo_idle_before_transition_log_rel}\` and
\`${pfifo_idle_before_transition_log_rel}\`. They report:
\`${pfifo_idle_before_transition_compare_line}\`.
This supersedes the older "native marker missing" idle-before hypothesis.
Both native and browser now emit \`cpu=idle-before-pfifo-transition\` at the
same idle edge, \`0x8001b02e -> 0x8001b02f\`, while PFIFO still has
\`dma_get=0x0388130c\`, \`dma_put=0x03881318\`, and 12 bytes left to consume.
The diagnostic PFIFO activity snapshot also aligns: both sides report
\`pfifo_activity_phase=puller-method-pgraph-return\`,
\`pfifo_activity_pfifo_lock_released=yes\`,
\`pfifo_activity_pgraph_locked=yes\`, and
\`pfifo_activity_final_transition_candidate=no\`. For this older
\`pfifo-activity-v1\` baseline artifact, the split is not PFIFO/PGRAPH activity
phase; it is the hard-IRQ/timer scheduling state at the following stream-idle
transition, where native already has \`CPU_INTERRUPT_HARD\` pending and browser
does not. The newer PFIFO pre-commit PIT artifact above moves past that
specific split and leaves the post-service loop flow as the front-most
diagnostic mismatch.
For the earlier callback-v1 artifact, the comparator reports
\`browser_extra_pic_line_assert_irqs=12,6\`,
\`browser_extra_lpc_route_assert_irqs=12,6\`, and no native counterparts. The
extra acknowledgements are therefore real browser-only routed IRQs:
\`0x3c\` is guest IRQ 12 through master cascade IRQ 2 and slave IRQ 4, and
\`0x36\` is master IRQ 6. The remaining gap is why browser asserts/services
those ACPI PM and MCPX ACI vectors after the first matching \`0x30\` service,
records a different first post-service loop edge, and never emits a
\`dashboard=xbe-executed\` marker. The PCRTC
vblank comparator still records
pending bits, phase counts, and PCRTC-driven PMC disable cycles for older or
normal-mode runs; use it to detect regressions back to the earlier browser-only
vblank cadence.
The browser build now has a diagnostic-only
\`XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE\` control with modes \`normal\`, \`off\`,
\`suppress-until-dashboard-observed\`, and \`suppress-until-entry-ready\`.
The page/worker path writes that mode into the wasm fixture filesystem so C-side
browser diagnostics do not depend on host \`getenv()\` propagation. Non-normal
runs emit sampled \`BOOT_MARK b6 nv2a=pcrtc-vblank-gate ...\` markers and must
still fail B6 unless they also produce true \`dashboard=xbe-executed\` and
native-reference visual-match evidence.
The browser artifact passes B4 display capture, B5 runtime evidence, and
browser-runtime \`xboxdash.xbe\` read correlation, but still fails the B6
checker at \`missing-xbe-executed-marker\`.
Sampled high aliases that overlap the XBE virtual range either are not mapped
at the image alias yet or resolve to different physical pages, and every
sampled native/browser TB remains \`cpu_mode=protected32 cpl=0 cs=0x0008\`. No
\`dashboard=xbe-executed\` marker appears. B6 is incomplete until
browser-runtime \`dashboard=xbe-executed\` and native reference-frame match
evidence exist.

Immediate B6 next work:

1. Investigate why post-load execution remains in protected-mode kernel TBs
   (\`cpl=0 cs=0x0008\`) after the dashboard XBE has been read, mapped, loaded,
   and its decoded entry point has become readable. Start from
   \`${preferred_b6_log_rel}\` and
   \`${native_post_iret_log_rel}\`. The v6 IRQ-source and callback-v1 artifacts
   remain useful historical source-attribution references, but the preferred B6
   artifact is now the front-most B5-pass browser reference.
   PFIFO/PGRAPH command progress is aligned, PCRTC-vblank shape is aligned, and
   the serviceable idle-loop probe now makes the browser first IRQ service begin
   from the same PC as native, \`0x8001b030\`. The PIT-only timer-pump
   diagnostic then removes the browser-only PM SCI/AC97 assertions and extra
   \`0x3c\`/\`0x36\` vectors while preserving the native-matching PIT/vector
   \`0x30\` service and first IRET. The fresh post-IRET reference then shows the
   preferred service/IRET frame matches for the 300s combined browser artifact.
   The next useful slice is therefore narrower: explain why native produces
   after-idle CPU interrupt samples while browser does not, and why the browser
   still never enters physically matching dashboard XBE code. Do not repeat the
   v4 larger early kernel-loop sampling
   experiment blindly; it re-samples earlier PGRAPH wait state and misses
   PFIFO stream-idle.
   Use the handoff, loop-cluster, IRQ-state, PCRTC, and IRET comparators as the
   concrete boundary before chasing renderer polish. The handoff comparator now
   emits \`handoff_blocker=...\` plus decoded branch/entry-target counts. The
   current callback-v1 and icount shift=0 artifacts both classify the remaining
   execution gap as \`both-high-alias-phys-mismatch\`, with
   \`browser_branch_phys_match_yes=0\` and
   \`browser_entry_target_phys_match_yes=0\`; decoded near-entry targets remain
   \`near-phys-mismatch\`, not proved dashboard handoff targets.
2. Use \`XEMU_BROWSER_BOOT_ICOUNT=<qemu-icount-value>\` only as a browser
   virtual-time diagnostic. The page/worker path logs
   \`BROWSER_DIAGNOSTIC name=browser_icount ...\`, appends
   \`-icount <value>\` to the wasm QEMU argv, and logs
   \`BROWSER_DIAGNOSTIC_APPLY name=browser_icount ... target=argv:-icount\`.
   The latest \`shift=10,sleep=off\` probe still timed out with heavy AC97
   callback activity after entry-ready. The latest \`shift=0,sleep=off\` probe,
   \`build-real-b3-matrix/browser-runtime-firefox-bidi-icount-shift0-v1.log\`,
   reached B4 display captures, \`dashboard=xbe-loaded\`, entry-ready evidence,
   no PM timer callback, and only one AC97 playback callback, but still timed
   out without \`dashboard=xbe-executed\` and fails the B6 checker at
   \`missing-xbe-read-marker\`. Treat this as evidence that lowering browser
   virtual time reduces the PM/AC97 divergence but does not by itself prove or
   produce dashboard execution.
3. Use \`XEMU_BROWSER_RUNTIME_BROWSER=firefox\` or \`chromium\` to select the
   Playwright engine in \`scripts/xbox-browser-runtime-smoke.sh\`.
4. Prefer Firefox BiDi for long browser-runtime probes until Playwright Firefox
   reaches comparable B4/IDE-read evidence.
5. Keep the real B3/B4/B5 matrix on
   \`XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi\` for the current combined
   browser-runtime \`xboxdash.xbe\` read baseline.
6. Capture native reference-frame hashes from the native dashboard path, then
   rerun browser smoke with \`XEMU_BROWSER_DASHBOARD_NATIVE_HASH=<hash>\`.
   The browser runtime will emit \`BROWSER_DASHBOARD_CAPTURE result=skip\`
   until true browser-runtime \`dashboard=xbe-executed\` exists; after that it
   can emit \`result=pass native_ref_match=yes\` only when the latest browser
   frame hash matches the supplied native reference hash.

## Evidence

| Item | Status | Meaning |
| --- | --- | --- |
| Synthetic aggregate gate | $(status_for synthetic_gate) | No-private-assets regression gate completed. |
| Docker build scaffold | $(status_for docker_build_scaffold) | Native and wasm Docker build scripts preserve required i386, TCI, browser-boot, and sysroot settings. |
| Synthetic B0 native/wasm | $(status_for b0_synthetic_native_wasm) | Both native and wasm constructed the Xbox machine. |
| Synthetic B1 native/wasm | $(status_for b1_synthetic_native_wasm) | Both native and wasm loaded synthetic firmware memory. |
| Synthetic B2 native/wasm | $(status_for b2_synthetic_native_wasm) | Both native and wasm initialized core Xbox devices. |
| Marker comparison | $(status_for synthetic_marker_compare) | Native and wasm marker sets match through the expected synthetic level. |
| Browser-block bridge | $(status_for b3_browser_block_bridge) | C-to-JS HDD open/read bridge is proven only with synthetic storage. |
| Browser host prerequisite | $(status_for b5_host_prereq) | COOP/COEP/CORP, artifacts, persistence, and host checks pass. |
| Browser runtime prerequisite | $(status_for b5_runtime_prereq) | Real browser synthetic run starts, logs, and times out deterministically. |
| Real fixture layout | $(status_for real_fixture_layout) | Ignored local fixture directory scaffolding is documented and tested without creating private assets. |
| Real fixture readiness | $(status_for real_fixture_ready) | Non-emulating check for private flash/HDD fixtures and fixed-size MCPX/EEPROM blobs. |
| Real fixture manifest | $(status_for real_fixture_manifest) | No-emulation handoff artifact with readiness and git privacy evidence. |
| Real fixture preflight | $(status_for real_fixture_preflight) | Real fixture discovery and size validation status. |
| Real B3 assets | $(status_for b3_real_assets) | Requires \`scripts/xbox-real-b3-evidence-check.sh\` to pass on the real matrix log. |
| Real B4 display | $(status_for b4_visible_display) | Requires B4 marker plus non-empty browser display capture evidence. |
| Real B5 browser | $(status_for b5_real_browser) | Requires \`scripts/xbox-browser-runtime-evidence-check.sh\` to pass on real selected-assets smoke. |

## Diagnostics

| Signal | Latest evidence |
| --- | --- |
| Fixture flash | ${flash_line:-not reported} |
| Fixture HDD | ${hdd_line:-not reported} |
| Fixture MCPX | ${mcpx_line:-not reported} |
| Fixture EEPROM | ${eeprom_line:-not reported} |
| Real B3 failure | ${real_b3_failure_line:-not reported} |
| Real B4 failure | ${display_failure_line:-not reported} |
| Real B5 failure | ${runtime_failure_line:-not reported} |
| B6 XBE read, any context | ${dashboard_xbe_read_line:-not reported} |
| B6 XBE read, browser-runtime | ${dashboard_xbe_browser_line:-not reported} |
| B6 XBE read, Playwright Chromium 300s | ${dashboard_xbe_playwright_long_line:-not reported} |
| Browser runtime, Playwright Firefox | ${playwright_firefox_runtime_line:-not reported} |
| B6 XBE read, Playwright Firefox | ${dashboard_xbe_playwright_firefox_line:-not reported} |
| Browser runtime, Firefox BiDi 300s | ${firefox_bidi_long_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi 300s | ${dashboard_xbe_firefox_bidi_long_line:-not reported} |
| Browser runtime, Firefox BiDi IDE poll | ${firefox_bidi_ide_poll_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi IDE poll | ${dashboard_xbe_firefox_bidi_ide_poll_line:-not reported} |
| Browser runtime, Firefox BiDi virtual probe | ${firefox_bidi_virtual_probe_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi virtual probe | ${dashboard_xbe_firefox_bidi_virtual_probe_line:-not reported} |
| B6 virtual probe, Firefox BiDi | ${dashboard_virtual_probe_firefox_bidi_line:-not reported} |
| Browser runtime, Firefox BiDi page probe | ${firefox_bidi_page_probe_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi page probe | ${dashboard_xbe_firefox_bidi_page_probe_line:-not reported} |
| B6 page probe, Firefox BiDi | ${dashboard_virtual_page_probe_firefox_bidi_line:-not reported} |
| Browser runtime, Firefox BiDi read-progress loaded | ${firefox_bidi_read_progress_loaded_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi read-progress loaded | ${dashboard_xbe_firefox_bidi_read_progress_loaded_line:-not reported} |
| B6 read progress, Firefox BiDi | ${dashboard_read_progress_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi | ${dashboard_xbe_loaded_firefox_bidi_line:-not reported} |
| B6 XBE executed, Firefox BiDi | ${dashboard_xbe_executed_firefox_bidi_line:-not reported} |
| Browser runtime, Firefox BiDi exec probe | ${firefox_bidi_exec_probe_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi exec probe | ${dashboard_xbe_firefox_bidi_exec_probe_line:-not reported} |
| B6 exec probe, Firefox BiDi | ${dashboard_exec_probe_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi exec probe | ${dashboard_xbe_loaded_firefox_bidi_exec_probe_line:-not reported} |
| B6 XBE executed, Firefox BiDi exec probe | ${dashboard_xbe_executed_firefox_bidi_exec_probe_line:-not reported} |
| Browser runtime, Firefox BiDi ret-target probe | ${firefox_bidi_ret_target_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi ret-target probe | ${dashboard_xbe_firefox_bidi_ret_target_line:-not reported} |
| B6 exec probe, Firefox BiDi ret-target | ${dashboard_exec_ret_target_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi ret-target probe | ${dashboard_xbe_loaded_firefox_bidi_ret_target_line:-not reported} |
| B6 XBE executed, Firefox BiDi ret-target probe | ${dashboard_xbe_executed_firefox_bidi_ret_target_line:-not reported} |
| Browser runtime, Firefox BiDi transition probe | ${firefox_bidi_transition_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi transition probe | ${dashboard_xbe_firefox_bidi_transition_line:-not reported} |
| B6 exec transition, Firefox BiDi | ${dashboard_transition_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi transition probe | ${dashboard_xbe_loaded_firefox_bidi_transition_line:-not reported} |
| B6 XBE executed, Firefox BiDi transition probe | ${dashboard_xbe_executed_firefox_bidi_transition_line:-not reported} |
| Browser runtime, Firefox BiDi edge probe | ${firefox_bidi_edge_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi edge probe | ${dashboard_xbe_firefox_bidi_edge_line:-not reported} |
| B6 exec edge, Firefox BiDi | ${dashboard_edge_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi edge probe | ${dashboard_xbe_loaded_firefox_bidi_edge_line:-not reported} |
| B6 XBE executed, Firefox BiDi edge probe | ${dashboard_xbe_executed_firefox_bidi_edge_line:-not reported} |
| Browser runtime, Firefox BiDi branch-target ${branch_target_label} | ${firefox_bidi_branch_target_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_xbe_firefox_bidi_branch_target_line:-not reported} |
| B6 call-mem32 target, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_branch_target_mem_firefox_bidi_line:-not reported} |
| B6 call-reg target, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_branch_target_reg_firefox_bidi_line:-not reported} |
| B6 exec edge, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_edge_branch_target_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_xbe_loaded_firefox_bidi_branch_target_line:-not reported} |
| B6 XBE executed, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_xbe_executed_firefox_bidi_branch_target_line:-not reported} |
| Browser runtime, Firefox BiDi entry probe | ${firefox_bidi_entry_probe_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi entry probe | ${dashboard_xbe_firefox_bidi_entry_probe_line:-not reported} |
| B6 entry probe, Firefox BiDi | ${dashboard_entry_probe_firefox_bidi_line:-not reported} |
| B6 entry probe ready, Firefox BiDi | ${dashboard_entry_probe_ready_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi entry probe | ${dashboard_xbe_loaded_firefox_bidi_entry_probe_line:-not reported} |
| B6 XBE executed, Firefox BiDi entry probe | ${dashboard_xbe_executed_firefox_bidi_entry_probe_line:-not reported} |
| Browser runtime, Firefox BiDi entry-target probe | ${firefox_bidi_entry_target_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi entry-target probe | ${dashboard_xbe_firefox_bidi_entry_target_line:-not reported} |
| B6 entry target, Firefox BiDi | ${dashboard_entry_target_firefox_bidi_line:-not reported} |
| B6 entry target near-phys-unknown, Firefox BiDi | ${dashboard_entry_target_near_unknown_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi entry-target probe | ${dashboard_xbe_loaded_firefox_bidi_entry_target_line:-not reported} |
| B6 XBE executed, Firefox BiDi entry-target probe | ${dashboard_xbe_executed_firefox_bidi_entry_target_line:-not reported} |
| B6 phys-compare runtime, Firefox BiDi | ${browser_phys_compare_runtime_line:-not reported} |
| B6 phys-compare count, Firefox BiDi | ${browser_phys_compare_count:-0} |
| B6 phys-compare no-match count, Firefox BiDi | ${browser_phys_compare_no_match_count:-0} |
| B6 phys-compare latest, Firefox BiDi | ${browser_phys_compare_line:-not reported} |
| B6 phys-compare match, Firefox BiDi | ${browser_phys_compare_match_line:-not reported} |
| B6 XBE loaded, Firefox BiDi phys-compare | ${browser_phys_compare_loaded_line:-not reported} |
| B6 entry probe ready, Firefox BiDi phys-compare | ${browser_phys_compare_entry_ready_line:-not reported} |
| B6 XBE executed, Firefox BiDi phys-compare | ${browser_phys_compare_executed_line:-not reported} |
| Browser runtime, Firefox BiDi ${dispatch_probe_label} | ${firefox_bidi_dispatch_probe_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi ${dispatch_probe_label} | ${dashboard_xbe_firefox_bidi_dispatch_probe_line:-not reported} |
| B6 dispatch probe, Firefox BiDi ${dispatch_probe_label} | ${dashboard_dispatch_probe_firefox_bidi_line:-not reported} |
| B6 dispatch no-register-candidate, Firefox BiDi ${dispatch_probe_label} | ${dashboard_dispatch_probe_no_reg_firefox_bidi_line:-not reported} |
| B6 XBE loaded, Firefox BiDi ${dispatch_probe_label} | ${dashboard_xbe_loaded_firefox_bidi_dispatch_probe_line:-not reported} |
| B6 XBE executed, Firefox BiDi ${dispatch_probe_label} | ${dashboard_xbe_executed_firefox_bidi_dispatch_probe_line:-not reported} |
| Browser runtime, Firefox BiDi ${kernel_loop_label} | ${firefox_bidi_kernel_loop_runtime_line:-not reported} |
| B6 XBE read, Firefox BiDi ${kernel_loop_label} | ${dashboard_xbe_firefox_bidi_kernel_loop_line:-not reported} |
| B6 kernel-loop probe, Firefox BiDi | ${dashboard_kernel_loop_firefox_bidi_line:-not reported} |
| B6 alias-compare latest, Firefox BiDi ${kernel_loop_label} | ${dashboard_alias_compare_firefox_bidi_line:-not reported} |
| B6 alias-compare no-match count, Firefox BiDi ${kernel_loop_label} | ${dashboard_alias_compare_no_match_count:-0} |
| B6 alias hash audit, Firefox BiDi ${kernel_loop_label} | ${dashboard_alias_hash_evidence_line:-not reported} |
| B6 target hash audit, Firefox BiDi target-hash-v1 | ${dashboard_target_hash_evidence_line:-not reported} |
| B6 kernel-loop NV2A wait, Firefox BiDi ${kernel_loop_label} | ${dashboard_kernel_loop_firefox_bidi_wait_state_line:-not reported} |
| B6 kernel-loop self sample, Firefox BiDi | ${dashboard_kernel_loop_firefox_bidi_self_line:-not reported} |
| B6 NV2A PMC access, Firefox BiDi ${kernel_loop_label} | ${dashboard_pmc_firefox_bidi_line:-not reported} |
| B6 NV2A PCRTC pending, Firefox BiDi ${kernel_loop_label} | ${dashboard_pmc_firefox_bidi_pcrtc_line:-not reported} |
| B6 NV2A IRQ source PCRTC, Firefox BiDi ${kernel_loop_label} | ${dashboard_irq_source_firefox_bidi_pcrtc_line:-not reported} |
| B6 NV2A IRQ source PGRAPH, Firefox BiDi ${kernel_loop_label} | ${dashboard_irq_source_firefox_bidi_pgraph_line:-not reported} |
| B6 NV2A IRQ line, Firefox BiDi ${kernel_loop_label} | ${dashboard_irq_line_firefox_bidi_line:-not reported} |
| B6 PCRTC vblank gate, Firefox BiDi ${kernel_loop_label} | ${dashboard_pcrtc_vblank_gate_firefox_bidi_line:-not reported} |
| B6 PGRAPH method count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_method_firefox_bidi_count:-0} |
| B6 PGRAPH method-window count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_method_window_firefox_bidi_count:-0} |
| B6 PGRAPH method-window latest, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_method_window_firefox_bidi_line:-not reported} |
| B6 PGRAPH NOP notify, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_method_firefox_bidi_nop_notify_line:-not reported} |
| B6 PGRAPH notify-error count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_notify_firefox_bidi_count:-0} |
| B6 PGRAPH notify-error latest, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_notify_firefox_bidi_line:-not reported} |
| B6 PGRAPH notify-clear count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_notify_clear_firefox_bidi_count:-0} |
| B6 PGRAPH notify-clear latest, Firefox BiDi ${kernel_loop_label} | ${dashboard_pgraph_notify_clear_firefox_bidi_line:-not reported} |
| B6 PGRAPH command-stream compare | ${pgraph_command_stream_compare_line:-not reported} |
| B6 post-command CPU/XBE handoff compare | ${post_command_handoff_compare_line:-not reported} |
| B6 post-command kernel-loop clusters | ${post_command_loop_clusters_line:-not reported} |
| B6 post-command NV2A IRQ/PMC state compare | ${post_command_irq_state_compare_line:-not reported} |
| B6 PCRTC vblank divergence compare | ${pcrtc_vblank_divergence_line:-not reported} |
| B6 interrupt-return frame compare | ${iret_frame_compare_line:-not reported} |
| B6 post-idle interrupt-flow compare | ${post_idle_interrupt_flow_compare_line:-not reported} |
| B6 TCG timer-pump attribution runtime | ${timer_pump_attribution_runtime_line:-not reported} |
| B6 TCG timer-pump attribution compare | ${timer_pump_attribution_compare_line:-not reported} |
| B6 PIT-only timer-pump runtime | ${pit_only_timer_pump_runtime_line:-not reported} |
| B6 PIT-only timer-pump compare | ${pit_only_timer_pump_compare_line:-not reported} |
| B6 PIT after-idle timer-pump runtime | ${pit_after_idle_timer_pump_runtime_line:-not reported} |
| B6 PIT after-idle timer-pump compare | ${pit_after_idle_timer_pump_compare_line:-not reported} |
| B6 PIT after-idle-full timer-pump runtime | ${pit_after_idle_full_timer_pump_runtime_line:-not reported} |
| B6 PIT after-idle-full timer-pump compare | ${pit_after_idle_full_timer_pump_compare_line:-not reported} |
| B6 PFIFO stream-idle boundary runtime | ${pfifo_boundary_timer_pump_runtime_line:-not reported} |
| B6 PFIFO stream-idle boundary compare | ${pfifo_stream_idle_boundary_compare_line:-not reported} |
| B6 PFIFO stream-idle transition runtime | ${pfifo_transition_timer_pump_runtime_line:-not reported} |
| B6 PFIFO stream-idle transition compare | ${pfifo_stream_idle_transition_compare_line:-not reported} |
| B6 PFIFO transition IRQ timing | ${pfifo_transition_irq_timing_line:-not reported} |
| B6 PFIFO transition PIT-at-transition runtime | ${pfifo_transition_pit_at_transition_runtime_line:-not reported} |
| B6 PFIFO transition PIT-at-transition compare | ${pfifo_transition_pit_at_transition_compare_line:-not reported} |
| B6 PFIFO transition PIT-at-transition flow | ${pfifo_transition_pit_at_transition_flow_line:-not reported} |
| B6 PFIFO pre-transition gate runtime | ${pfifo_transition_gate_runtime_line:-not reported} |
| B6 PFIFO pre-transition gate latest | ${pfifo_transition_gate_line:-not reported} |
| B6 PFIFO pre-transition gate compare | ${pfifo_transition_gate_compare_line:-not reported} |
| B6 PFIFO activity-gated pre-transition runtime | ${pfifo_transition_activity_runtime_line:-not reported} |
| B6 PFIFO activity-gated pre-transition gate | ${pfifo_transition_activity_gate_line:-not reported} |
| B6 PFIFO activity-gated pre-transition timer | ${pfifo_transition_activity_timer_line:-not reported} |
| B6 PFIFO activity-gated pre-transition compare | ${pfifo_transition_activity_compare_line:-not reported} |
| B6 PFIFO activity-gated pre-transition flow | ${pfifo_transition_activity_flow_line:-not reported} |
| B6 PFIFO pre-commit PIT runtime | ${pfifo_transition_pre_commit_runtime_line:-not reported} |
| B6 PFIFO pre-commit PIT marker | ${pfifo_transition_pre_commit_marker_line:-not reported} |
| B6 PFIFO pre-commit PIT compare | ${pfifo_transition_pre_commit_irq_timing_line:-not reported} |
| B6 PFIFO pre-commit PIT flow | ${pfifo_transition_pre_commit_flow_line:-not reported} |
| B6 preferred browser runtime | ${preferred_b6_runtime_evidence_line:-not reported} |
| B6 preferred display capture | ${preferred_b6_display_line:-not reported} |
| B6 preferred dashboard loaded | ${preferred_b6_dashboard_line:-not reported} |
| B6 preferred section map diagnostic | ${preferred_b6_section_map_line:-not reported} |
| B6 preferred IRET compare | ${preferred_b6_iret_line:-not reported} |
| B6 preferred loop compare | ${preferred_b6_loop_line:-not reported} |
| B6 preferred flow compare | ${preferred_b6_flow_line:-not reported} |
| B6 idle-before-PFIFO transition runtime | ${pfifo_idle_before_transition_runtime_line:-not reported} |
| B6 idle-before-PFIFO transition compare | ${pfifo_idle_before_transition_compare_line:-not reported} |
| B6 PFIFO progress count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_firefox_bidi_count:-0} |
| B6 PFIFO puller-method count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_firefox_bidi_puller_method_count:-0} |
| B6 PFIFO latest marker, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_firefox_bidi_line:-not reported} |
| B6 PFIFO window count, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_window_firefox_bidi_count:-0} |
| B6 PFIFO window latest, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_window_firefox_bidi_line:-not reported} |
| B6 PFIFO context wait, Firefox BiDi ${kernel_loop_label} | ${dashboard_pfifo_firefox_bidi_context_wait_line:-not reported} |
| B6 XBE loaded, Firefox BiDi ${kernel_loop_label} | ${dashboard_xbe_loaded_firefox_bidi_kernel_loop_line:-not reported} |
| B6 XBE executed, Firefox BiDi ${kernel_loop_label} | ${dashboard_xbe_executed_firefox_bidi_kernel_loop_line:-not reported} |
| B6 XBE loaded, native TCG hook | ${native_tcg_exec_loaded_line:-not reported} |
| B6 XBE executed, native TCG hook | ${native_tcg_exec_executed_line:-not reported} |
| B6 exec probe, native TCG hook | ${native_exec_probe_line:-not reported} |
| B6 XBE loaded, native exec probe | ${native_exec_probe_loaded_line:-not reported} |
| B6 XBE executed, native exec probe | ${native_exec_probe_executed_line:-not reported} |
| B6 exec probe, native high-alias check | ${native_high_alias_exec_probe_line:-not reported} |
| B6 XBE loaded, native high-alias check | ${native_high_alias_loaded_line:-not reported} |
| B6 XBE executed, native high-alias check | ${native_high_alias_executed_line:-not reported} |
| B6 exec probe, native ret-target | ${native_ret_target_exec_probe_line:-not reported} |
| B6 XBE loaded, native ret-target probe | ${native_ret_target_loaded_line:-not reported} |
| B6 XBE executed, native ret-target probe | ${native_ret_target_executed_line:-not reported} |
| B6 exec transition, native | ${native_transition_exec_probe_line:-not reported} |
| B6 XBE loaded, native transition probe | ${native_transition_loaded_line:-not reported} |
| B6 XBE executed, native transition probe | ${native_transition_executed_line:-not reported} |
| B6 exec edge, native | ${native_edge_exec_probe_line:-not reported} |
| B6 XBE loaded, native edge probe | ${native_edge_loaded_line:-not reported} |
| B6 XBE executed, native edge probe | ${native_edge_executed_line:-not reported} |
| B6 call-mem32 target, native branch-target probe | ${native_branch_target_mem_line:-not reported} |
| B6 call-reg target, native branch-target probe | ${native_branch_target_reg_line:-not reported} |
| B6 XBE loaded, native branch-target probe | ${native_branch_target_loaded_line:-not reported} |
| B6 XBE executed, native branch-target probe | ${native_branch_target_executed_line:-not reported} |
| B6 entry probe, native | ${native_entry_probe_line:-not reported} |
| B6 entry probe ready, native | ${native_entry_probe_ready_line:-not reported} |
| B6 XBE loaded, native entry probe | ${native_entry_probe_loaded_line:-not reported} |
| B6 XBE executed, native entry probe | ${native_entry_probe_executed_line:-not reported} |
| B6 entry target, native | ${native_entry_target_line:-not reported} |
| B6 entry target near-phys-unknown, native | ${native_entry_target_near_unknown_line:-not reported} |
| B6 XBE loaded, native entry-target probe | ${native_entry_target_loaded_line:-not reported} |
| B6 XBE executed, native entry-target probe | ${native_entry_target_executed_line:-not reported} |
| B6 phys-compare count, native | ${native_phys_compare_count:-0} |
| B6 phys-compare no-match count, native | ${native_phys_compare_no_match_count:-0} |
| B6 phys-compare latest, native | ${native_phys_compare_line:-not reported} |
| B6 phys-compare match, native | ${native_phys_compare_match_line:-not reported} |
| B6 XBE loaded, native phys-compare | ${native_phys_compare_loaded_line:-not reported} |
| B6 entry probe ready, native phys-compare | ${native_phys_compare_entry_ready_line:-not reported} |
| B6 XBE executed, native phys-compare | ${native_phys_compare_executed_line:-not reported} |
| B6 dispatch probe, native | ${native_dispatch_probe_line:-not reported} |
| B6 dispatch no-register-candidate, native | ${native_dispatch_probe_no_reg_line:-not reported} |
| B6 XBE loaded, native dispatch probe | ${native_dispatch_probe_loaded_line:-not reported} |
| B6 XBE executed, native dispatch probe | ${native_dispatch_probe_executed_line:-not reported} |
| B6 kernel-loop probe, native ${kernel_loop_label} | ${native_kernel_loop_line:-not reported} |
| B6 kernel-loop NV2A wait, native ${kernel_loop_label} | ${native_kernel_loop_wait_state_line:-not reported} |
| B6 kernel-loop transition self sample, native | ${native_kernel_loop_transition_self_line:-not reported} |
| B6 kernel-loop edge self sample, native | ${native_kernel_loop_edge_self_line:-not reported} |
| B6 NV2A PMC access, native ${kernel_loop_label} | ${native_pmc_line:-not reported} |
| B6 NV2A PGRAPH pending, native ${kernel_loop_label} | ${native_pmc_pgraph_line:-not reported} |
| B6 NV2A IRQ source PGRAPH, native ${kernel_loop_label} | ${native_irq_source_pgraph_line:-not reported} |
| B6 NV2A IRQ source PCRTC, native ${kernel_loop_label} | ${native_irq_source_pcrtc_line:-not reported} |
| B6 NV2A IRQ line, native ${kernel_loop_label} | ${native_irq_line:-not reported} |
| B6 PGRAPH method count, native ${kernel_loop_label} | ${native_pgraph_method_count:-0} |
| B6 PGRAPH method-window count, native ${kernel_loop_label} | ${native_pgraph_method_window_count:-0} |
| B6 PGRAPH method-window latest, native ${kernel_loop_label} | ${native_pgraph_method_window_line:-not reported} |
| B6 PGRAPH NOP notify, native ${kernel_loop_label} | ${native_pgraph_method_nop_notify_line:-not reported} |
| B6 PGRAPH notify-error count, native ${kernel_loop_label} | ${native_pgraph_notify_count:-0} |
| B6 PGRAPH notify-error latest, native ${kernel_loop_label} | ${native_pgraph_notify_line:-not reported} |
| B6 PGRAPH notify-clear count, native ${kernel_loop_label} | ${native_pgraph_notify_clear_count:-0} |
| B6 PGRAPH notify-clear latest, native ${kernel_loop_label} | ${native_pgraph_notify_clear_line:-not reported} |
| B6 PFIFO progress count, native ${kernel_loop_label} | ${native_pfifo_count:-0} |
| B6 PFIFO puller-method count, native ${kernel_loop_label} | ${native_pfifo_puller_method_count:-0} |
| B6 PFIFO latest marker, native ${kernel_loop_label} | ${native_pfifo_line:-not reported} |
| B6 PFIFO window count, native ${kernel_loop_label} | ${native_pfifo_window_count:-0} |
| B6 PFIFO window latest, native ${kernel_loop_label} | ${native_pfifo_window_line:-not reported} |
| B6 PFIFO context wait, native ${kernel_loop_label} | ${native_pfifo_context_wait_line:-not reported} |
| B6 XBE loaded, native ${kernel_loop_label} | ${native_kernel_loop_loaded_line:-not reported} |
| B6 XBE executed, native ${kernel_loop_label} | ${native_kernel_loop_executed_line:-not reported} |
| B6 native reference evidence | ${native_reference_evidence_line:-not reported} |
| B6 dashboard loaded | ${dashboard_loaded_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi IDE poll | ${dashboard_loaded_ide_poll_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi virtual probe | ${dashboard_loaded_virtual_probe_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi page probe | ${dashboard_loaded_page_probe_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi read-progress loaded | ${dashboard_loaded_read_progress_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi exec probe | ${dashboard_loaded_exec_probe_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi ret-target probe | ${dashboard_loaded_ret_target_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi transition probe | ${dashboard_loaded_transition_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi edge probe | ${dashboard_loaded_edge_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi branch-target ${branch_target_label} | ${dashboard_loaded_branch_target_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi entry probe | ${dashboard_loaded_entry_probe_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi entry-target probe | ${dashboard_loaded_entry_target_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi ${dispatch_probe_label} | ${dashboard_loaded_dispatch_probe_line:-not reported} |
| B6 dashboard loaded, Firefox BiDi ${kernel_loop_label} | ${dashboard_loaded_kernel_loop_line:-not reported} |
| Next command | reason=${next_reason:-unknown} command=${next_command:-unknown} |

## Next Commands

Ask the machine-readable helper for the next command:

\`\`\`sh
scripts/xbox-boot-next-step.sh
\`\`\`

Run the no-private-assets gate:

\`\`\`sh
scripts/xbox-browser-boot-verify-synthetic.sh
\`\`\`

After local fixtures exist, validate them first:

\`\`\`sh
scripts/xbox-real-fixtures-ready.sh
XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh
\`\`\`

Then run the real B3 matrix:

\`\`\`sh
scripts/xbox-real-b3-matrix.sh
\`\`\`

For full completion audit:

\`\`\`sh
scripts/xbox-boot-completion-audit.sh
\`\`\`

## Raw Evidence

\`\`\`text
$(cat "${tmp_summary}")
\`\`\`
EOF

printf 'BOOT_EVIDENCE_REPORT result=pass output=%s summary=%s next=%s\n' \
    "${output}" "${summary_result}" "${next_step}"
