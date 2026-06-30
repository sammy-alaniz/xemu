#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/xbox-b6-current-boundary.sh [--native-log <log>] [--browser-log <log>] [--native-proof-log <log>]

Runs the focused B6 evidence gate and current native/browser comparators against
the frozen B6 baseline logs. This is a read-only diagnostic helper; it does not
start emulation and it does not inspect private fixture contents.

Defaults:
  native log:       build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log, when present
  browser log:      build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log, when present
  native proof log: build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log, when present
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
default_native_log="${repo_root}/build-real-b3-matrix/native-post-iret-flow-v1/boot-smoke.log"
if [ -f "${repo_root}/build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log" ]; then
    default_native_log="${repo_root}/build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log"
fi
native_log="${XEMU_B6_NATIVE_LOG:-${default_native_log}}"
default_native_memory_watch_log=""
if [ -f "${repo_root}/build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log" ]; then
    default_native_memory_watch_log="${repo_root}/build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log"
elif [ -f "${repo_root}/build-real-b3-matrix/native-memory-watch-0x3a890-v2/boot-smoke.log" ]; then
    default_native_memory_watch_log="${repo_root}/build-real-b3-matrix/native-memory-watch-0x3a890-v2/boot-smoke.log"
fi
native_memory_watch_log="${XEMU_B6_NATIVE_MEMORY_WATCH_LOG:-${default_native_memory_watch_log}}"
default_browser_log="${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log"
if [ -f "${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-v2-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-memory-watch-write-0x3a890-v1-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-memory-sample-0x3a890-full-baseline-v1-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-then-empty-filtered-limit4-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-pretransition-then-empty-filtered-limit4-v1-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-limit4-v1-combined.log"
elif [ -f "${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-v1-combined.log" ]; then
    default_browser_log="${repo_root}/build-real-b3-matrix/browser-runtime-firefox-bidi-headless-gate-bounded-no-tcg-v1-combined.log"
fi
browser_log="${XEMU_B6_BROWSER_LOG:-${default_browser_log}}"
native_proof_log="${XEMU_B6_NATIVE_PROOF_LOG:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --native-log)
            native_log="${2:-}"
            shift 2
            ;;
        --browser-log)
            browser_log="${2:-}"
            shift 2
            ;;
        --native-proof-log)
            native_proof_log="${2:-}"
            shift 2
            ;;
        *)
            printf 'B6_CURRENT_BOUNDARY result=fail reason=unknown-arg arg=%s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

abspath() {
    local path="$1"

    case "${path}" in
        /*)
            printf '%s' "${path}"
            ;;
        *)
            printf '%s/%s' "${repo_root}" "${path}"
            ;;
    esac
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

last_line_with_prefix() {
    local text="$1"
    local prefix="$2"

    printf '%s\n' "${text}" | grep "^${prefix}" | tail -n 1 || true
}

run_capture() {
    local output_var="$1"
    local status_var="$2"
    local output
    local status

    shift 2
    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e
    printf -v "${output_var}" '%s' "${output}"
    printf -v "${status_var}" '%s' "${status}"
}

print_output() {
    local output="$1"

    if [ -n "${output}" ]; then
        printf '%s\n' "${output}"
    fi
}

strict_xbe_executed_for() {
    local log_path="$1"
    local expected_context="$2"
    local line
    local context
    local phys_match
    local section_flags

    while IFS= read -r line; do
        case "${line}" in
            "BOOT_MARK b6 dashboard=xbe-executed "*) ;;
            *) continue ;;
        esac

        context="$(value_for "${line}" context)"
        phys_match="$(value_for "${line}" phys_match)"
        section_flags="$(value_for "${line}" section_flags)"
        if [ "${context}" != "${expected_context}" ]; then
            continue
        fi
        if [ "${phys_match}" != "yes" ]; then
            continue
        fi
        if [ -z "${section_flags}" ] || [ "${section_flags}" = "missing" ]; then
            continue
        fi
        if [ $((section_flags & 0x4)) -eq 0 ]; then
            continue
        fi
        printf 'yes'
        return
    done <"${log_path}"

    printf 'no'
}

detector_proof_for() {
    local log_path="$1"
    local expected_context="$2"
    local line
    local context
    local result

    while IFS= read -r line; do
        case "${line}" in
            "BOOT_MARK b6 dashboard=xbe-executed-detector-proof "*) ;;
            *) continue ;;
        esac

        context="$(value_for "${line}" context)"
        result="$(value_for "${line}" result)"
        if [ "${context}" != "${expected_context}" ]; then
            continue
        fi
        if [ "${result}" = "pass" ]; then
            printf 'pass'
            return
        fi
        printf 'fail'
        return
    done <"${log_path}"

    printf 'missing'
}

native_log="$(abspath "${native_log}")"
browser_log="$(abspath "${browser_log}")"
if [ -n "${native_memory_watch_log}" ]; then
    native_memory_watch_log="$(abspath "${native_memory_watch_log}")"
fi
if [ -z "${native_proof_log}" ]; then
    candidate_native_proof_log="${repo_root}/build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log"
    if [ -f "${candidate_native_proof_log}" ]; then
        native_proof_log="${candidate_native_proof_log}"
    else
        candidate_native_proof_log="${repo_root}/build-real-b3-matrix/native-xbe-detector-proof-v1/boot-smoke.log"
        if [ -f "${candidate_native_proof_log}" ]; then
            native_proof_log="${candidate_native_proof_log}"
        else
            native_proof_log="${native_log}"
        fi
    fi
else
    native_proof_log="$(abspath "${native_proof_log}")"
fi

if [ ! -f "${native_log}" ]; then
    printf 'B6_CURRENT_BOUNDARY result=fail reason=missing-native-log native_log=%s\n' "$(repo_relative_path "${native_log}")" >&2
    exit 2
fi

if [ ! -f "${browser_log}" ]; then
    printf 'B6_CURRENT_BOUNDARY result=fail reason=missing-browser-log browser_log=%s\n' "$(repo_relative_path "${browser_log}")" >&2
    exit 2
fi

if [ ! -f "${native_proof_log}" ]; then
    printf 'B6_CURRENT_BOUNDARY result=fail reason=missing-native-proof-log native_proof_log=%s\n' "$(repo_relative_path "${native_proof_log}")" >&2
    exit 2
fi

if [ -n "${native_memory_watch_log}" ] && [ ! -f "${native_memory_watch_log}" ]; then
    printf 'B6_CURRENT_BOUNDARY result=fail reason=missing-native-memory-watch-log native_memory_watch_log=%s\n' "$(repo_relative_path "${native_memory_watch_log}")" >&2
    exit 2
fi

printf 'B6_CURRENT_BOUNDARY_INPUT native_log=%s browser_log=%s native_proof_log=%s native_memory_watch_log=%s\n' \
    "$(repo_relative_path "${native_log}")" \
    "$(repo_relative_path "${browser_log}")" \
    "$(repo_relative_path "${native_proof_log}")" \
    "${native_memory_watch_log:+$(repo_relative_path "${native_memory_watch_log}")}"

run_capture loaded_output loaded_status \
    "${repo_root}/scripts/xbox-dashboard-loaded-evidence-check.sh" "${browser_log}"
print_output "${loaded_output}"

run_capture section_map_output section_map_status \
    "${repo_root}/scripts/xbox-dashboard-section-map-evidence-check.sh" "${browser_log}"
print_output "${section_map_output}"

run_capture native_actual_output native_actual_status \
    "${repo_root}/scripts/xbox-native-actual-xbe-execution-check.py" \
    "${native_proof_log}" \
    --context native-headless
print_output "${native_actual_output}"

run_capture native_handoff_output native_handoff_status \
    "${repo_root}/scripts/xbox-native-headless-handoff-check.py" \
    "${native_proof_log}" \
    --context native-headless
print_output "${native_handoff_output}"

run_capture iret_output iret_status \
    "${repo_root}/scripts/xbox-iret-frame-compare.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${iret_output}"

run_capture loop_output loop_status \
    "${repo_root}/scripts/xbox-post-command-loop-clusters.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${loop_output}"

run_capture memory_poll_output memory_poll_status \
    "${repo_root}/scripts/xbox-post-service-memory-poll-compare.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${memory_poll_output}"

run_capture watch_edge_output watch_edge_status \
    "${repo_root}/scripts/xbox-post-service-watch-edge-compare.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${watch_edge_output}"

run_capture pre_service_output pre_service_status \
    "${repo_root}/scripts/xbox-pre-service-tick-gap-compare.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${pre_service_output}"

if [ -n "${native_memory_watch_log}" ]; then
run_capture memory_watch_timeline_output memory_watch_timeline_status \
        "${repo_root}/scripts/xbox-memory-watch-timeline-compare.py" \
        --native-log "${native_memory_watch_log}" \
        --browser-log "${browser_log}"
else
    memory_watch_timeline_output="MEMORY_WATCH_TIMELINE_COMPARE result=skip reason=missing-native-watch-log"
    memory_watch_timeline_status=0
fi
print_output "${memory_watch_timeline_output}"

run_capture headless_pump_output headless_pump_status \
    "${repo_root}/scripts/xbox-headless-pump-placement-compare.py" \
    --browser-log "${browser_log}"
print_output "${headless_pump_output}"

run_capture flow_output flow_status \
    "${repo_root}/scripts/xbox-post-idle-interrupt-flow-compare.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${flow_output}"

run_capture pfifo_output pfifo_status \
    "${repo_root}/scripts/xbox-pfifo-transition-irq-timing.py" \
    --native-log "${native_log}" \
    --browser-log "${browser_log}"
print_output "${pfifo_output}"

loaded_line="$(last_line_with_prefix "${loaded_output}" DASHBOARD_LOADED_EVIDENCE)"
section_map_line="$(last_line_with_prefix "${section_map_output}" DASHBOARD_SECTION_MAP_EVIDENCE)"
native_actual_line="$(last_line_with_prefix "${native_actual_output}" NATIVE_ACTUAL_XBE_EXECUTION)"
native_handoff_line="$(last_line_with_prefix "${native_handoff_output}" NATIVE_HEADLESS_HANDOFF)"
iret_line="$(last_line_with_prefix "${iret_output}" IRET_FRAME_COMPARE)"
loop_line="$(last_line_with_prefix "${loop_output}" POST_COMMAND_LOOP_CLUSTERS)"
memory_poll_line="$(last_line_with_prefix "${memory_poll_output}" POST_SERVICE_MEMORY_POLL_COMPARE)"
watch_edge_line="$(last_line_with_prefix "${watch_edge_output}" POST_SERVICE_WATCH_EDGE_COMPARE)"
pre_service_line="$(last_line_with_prefix "${pre_service_output}" PRE_SERVICE_TICK_GAP_COMPARE)"
memory_watch_timeline_line="$(last_line_with_prefix "${memory_watch_timeline_output}" MEMORY_WATCH_TIMELINE_COMPARE)"
headless_pump_line="$(last_line_with_prefix "${headless_pump_output}" HEADLESS_PUMP_PLACEMENT_COMPARE)"
flow_line="$(last_line_with_prefix "${flow_output}" POST_IDLE_INTERRUPT_FLOW_COMPARE)"
pfifo_line="$(last_line_with_prefix "${pfifo_output}" PFIFO_TRANSITION_IRQ_TIMING_COMPARE)"

loaded_result="$(value_for "${loaded_line}" result)"
loaded_reason="$(value_for "${loaded_line}" reason)"
section_map_result="$(value_for "${section_map_line}" result)"
native_actual_result="$(value_for "${native_actual_line}" result)"
native_actual_reason="$(value_for "${native_actual_line}" reason)"
native_actual_direct_entry_pc="$(value_for "${native_actual_line}" direct_entry_pc)"
native_actual_first_entry_cpu="$(value_for "${native_actual_line}" detector_cpu_eip)"
native_actual_first_after_idle_edge="$(value_for "${native_actual_line}" first_after_idle_edge)"
native_actual_after_idle_cpu_interrupts="$(value_for "${native_actual_line}" after_idle_cpu_interrupt_nonzero)"
native_handoff_result="$(value_for "${native_handoff_line}" result)"
native_handoff_state="$(value_for "${native_handoff_line}" terminal_state)"
native_handoff_boot_reason="$(value_for "${native_handoff_line}" boot_result_reason)"
native_handoff_short_animation="$(value_for "${native_handoff_line}" short_animation)"
native_handoff_native_reference="$(value_for "${native_handoff_line}" native_reference)"
native_handoff_stream_idle_eip="$(value_for "${native_handoff_line}" latest_stream_idle_eip)"
native_handoff_stream_idle_interrupt="$(value_for "${native_handoff_line}" latest_stream_idle_cpu_interrupt_request)"
native_handoff_after_idle_top_edge="$(value_for "${native_handoff_line}" after_idle_top_edge)"
native_handoff_after_idle_interrupts="$(value_for "${native_handoff_line}" after_idle_cpu_interrupt_nonzero)"
iret_result="$(value_for "${iret_line}" result)"
iret_divergence="$(value_for "${iret_line}" divergence)"
loop_result="$(value_for "${loop_line}" result)"
loop_divergence="$(value_for "${loop_line}" divergence)"
after_idle_divergence="$(value_for "${loop_line}" after_idle_divergence)"
after_idle_cpu_interrupt_divergence="$(value_for "${loop_line}" after_idle_cpu_interrupt_divergence)"
memory_poll_result="$(value_for "${memory_poll_line}" result)"
memory_poll_divergence="$(value_for "${memory_poll_line}" divergence)"
shared_memory_poll_addr="$(value_for "${memory_poll_line}" shared_memory_poll_addr)"
native_shared_memory_poll_value="$(value_for "${memory_poll_line}" native_shared_memory_poll_value)"
browser_shared_memory_poll_value="$(value_for "${memory_poll_line}" browser_shared_memory_poll_value)"
shared_memory_poll_tick_unit="$(value_for "${memory_poll_line}" shared_memory_poll_tick_unit)"
native_shared_memory_poll_ticks="$(value_for "${memory_poll_line}" native_shared_memory_poll_ticks)"
browser_shared_memory_poll_ticks="$(value_for "${memory_poll_line}" browser_shared_memory_poll_ticks)"
shared_memory_poll_tick_delta="$(value_for "${memory_poll_line}" shared_memory_poll_tick_delta)"
shared_memory_poll_tick_relation="$(value_for "${memory_poll_line}" shared_memory_poll_tick_relation)"
native_main_loop_timer_memory_watch_samples="$(value_for "${memory_poll_line}" native_main_loop_timer_memory_watch_samples)"
browser_main_loop_timer_memory_watch_samples="$(value_for "${memory_poll_line}" browser_main_loop_timer_memory_watch_samples)"
native_main_loop_timer_max_memory_watch_value="$(value_for "${memory_poll_line}" native_main_loop_timer_max_memory_watch_value)"
browser_main_loop_timer_max_memory_watch_value="$(value_for "${memory_poll_line}" browser_main_loop_timer_max_memory_watch_value)"
native_main_loop_timer_max_memory_watch_ticks="$(value_for "${memory_poll_line}" native_main_loop_timer_max_memory_watch_ticks)"
browser_main_loop_timer_max_memory_watch_ticks="$(value_for "${memory_poll_line}" browser_main_loop_timer_max_memory_watch_ticks)"
native_main_loop_timer_last_memory_watch_value="$(value_for "${memory_poll_line}" native_main_loop_timer_last_memory_watch_value)"
browser_main_loop_timer_last_memory_watch_value="$(value_for "${memory_poll_line}" browser_main_loop_timer_last_memory_watch_value)"
native_main_loop_timer_last_memory_watch_ticks="$(value_for "${memory_poll_line}" native_main_loop_timer_last_memory_watch_ticks)"
browser_main_loop_timer_last_memory_watch_ticks="$(value_for "${memory_poll_line}" browser_main_loop_timer_last_memory_watch_ticks)"
native_post_service_top_edge="$(value_for "${memory_poll_line}" native_top_edge)"
browser_post_service_top_edge="$(value_for "${memory_poll_line}" browser_top_edge)"
watch_edge_result="$(value_for "${watch_edge_line}" result)"
watch_edge_divergence="$(value_for "${watch_edge_line}" divergence)"
watch_edge_pre_tick_delta="$(value_for "${watch_edge_line}" pre_tick_delta)"
watch_edge_post_tick_delta="$(value_for "${watch_edge_line}" post_tick_delta)"
watch_edge_block_delta_match="$(value_for "${watch_edge_line}" block_delta_match)"
native_watch_edge_pre_ticks="$(value_for "${watch_edge_line}" native_pre_ticks)"
browser_watch_edge_pre_ticks="$(value_for "${watch_edge_line}" browser_pre_ticks)"
native_watch_edge_post_ticks="$(value_for "${watch_edge_line}" native_post_ticks)"
browser_watch_edge_post_ticks="$(value_for "${watch_edge_line}" browser_post_ticks)"
native_watch_edge_block_delta_ticks="$(value_for "${watch_edge_line}" native_block_delta_ticks)"
browser_watch_edge_block_delta_ticks="$(value_for "${watch_edge_line}" browser_block_delta_ticks)"
native_watch_edge_pre_edge="$(value_for "${watch_edge_line}" native_pre_edge)"
browser_watch_edge_pre_edge="$(value_for "${watch_edge_line}" browser_pre_edge)"
native_watch_edge_post_edge="$(value_for "${watch_edge_line}" native_post_edge)"
browser_watch_edge_post_edge="$(value_for "${watch_edge_line}" browser_post_edge)"
pre_service_result="$(value_for "${pre_service_line}" result)"
pre_service_divergence="$(value_for "${pre_service_line}" divergence)"
pre_service_tick_delta="$(value_for "${pre_service_line}" first_watch_read_tick_delta)"
pre_service_native_first_read_ticks="$(value_for "${pre_service_line}" native_first_watch_read_ticks)"
pre_service_browser_first_read_ticks="$(value_for "${pre_service_line}" browser_first_watch_read_ticks)"
pre_service_native_first_read_edge="$(value_for "${pre_service_line}" native_first_watch_read_edge)"
pre_service_browser_first_read_edge="$(value_for "${pre_service_line}" browser_first_watch_read_edge)"
pre_service_browser_timer_source="$(value_for "${pre_service_line}" browser_first_timer_source)"
pre_service_browser_timer_ticks="$(value_for "${pre_service_line}" browser_first_timer_watch_ticks)"
pre_service_browser_read_before_write="$(value_for "${pre_service_line}" browser_first_watch_read_before_write)"
pre_service_browser_write_delta="$(value_for "${pre_service_line}" browser_first_watch_write_delta_from_read)"
pre_service_browser_service_eip="$(value_for "${pre_service_line}" browser_first_service_eip)"
memory_watch_timeline_result="$(value_for "${memory_watch_timeline_line}" result)"
memory_watch_timeline_divergence="$(value_for "${memory_watch_timeline_line}" divergence)"
memory_watch_timeline_shared_delta="$(value_for "${memory_watch_timeline_line}" shared_poll_tick_delta)"
native_watch_install="$(value_for "${memory_watch_timeline_line}" native_watch_install)"
browser_watch_install="$(value_for "${memory_watch_timeline_line}" browser_watch_install)"
native_watch_access_events="$(value_for "${memory_watch_timeline_line}" native_watch_access_events)"
browser_watch_access_events="$(value_for "${memory_watch_timeline_line}" browser_watch_access_events)"
native_watch_write_events="$(value_for "${memory_watch_timeline_line}" native_watch_write_events)"
browser_watch_write_events="$(value_for "${memory_watch_timeline_line}" browser_watch_write_events)"
native_first_watch_write_eip="$(value_for "${memory_watch_timeline_line}" native_first_watch_write_eip)"
browser_first_watch_write_eip="$(value_for "${memory_watch_timeline_line}" browser_first_watch_write_eip)"
native_first_watch_write_ticks="$(value_for "${memory_watch_timeline_line}" native_first_watch_write_ticks)"
browser_first_watch_write_ticks="$(value_for "${memory_watch_timeline_line}" browser_first_watch_write_ticks)"
native_first_watch_write_value="$(value_for "${memory_watch_timeline_line}" native_first_watch_write_value)"
browser_first_watch_write_value="$(value_for "${memory_watch_timeline_line}" browser_first_watch_write_value)"
browser_last_watch_write_value="$(value_for "${memory_watch_timeline_line}" browser_last_watch_write_value)"
browser_first_shared_poll_ticks="$(value_for "${memory_watch_timeline_line}" browser_first_shared_poll_ticks)"
native_first_shared_poll_ticks="$(value_for "${memory_watch_timeline_line}" native_first_shared_poll_ticks)"
headless_pump_result="$(value_for "${headless_pump_line}" result)"
headless_pump_divergence="$(value_for "${headless_pump_line}" divergence)"
headless_pump_host_ready_before_boundary="$(value_for "${headless_pump_line}" host_ready_before_boundary)"
headless_pump_timer_before_boundary="$(value_for "${headless_pump_line}" timer_before_boundary)"
headless_pump_timer_after_boundary="$(value_for "${headless_pump_line}" timer_after_boundary)"
headless_pump_first_timer_watch_zero="$(value_for "${headless_pump_line}" first_timer_watch_zero)"
headless_pump_first_memory_write_zero="$(value_for "${headless_pump_line}" first_memory_write_zero)"
headless_pump_first_host_ready_line="$(value_for "${headless_pump_line}" first_host_ready_line)"
headless_pump_boundary_line="$(value_for "${headless_pump_line}" boundary_line)"
headless_pump_first_timer_line="$(value_for "${headless_pump_line}" first_timer_line)"
headless_pump_first_timer_placement="$(value_for "${headless_pump_line}" first_timer_placement)"
flow_result="$(value_for "${flow_line}" result)"
flow_divergence="$(value_for "${flow_line}" divergence)"
flow_timer_divergence="$(value_for "${flow_line}" timer_divergence)"
flow_mismatch_index="$(value_for "${flow_line}" first_flow_mismatch_index)"
native_main_loop_timer_events="$(value_for "${flow_line}" native_main_loop_timer_events)"
browser_main_loop_timer_events="$(value_for "${flow_line}" browser_main_loop_timer_events)"
native_main_loop_timer_sources="$(value_for "${flow_line}" native_main_loop_timer_sources)"
browser_main_loop_timer_sources="$(value_for "${flow_line}" browser_main_loop_timer_sources)"
native_main_loop_timer_progress_events="$(value_for "${flow_line}" native_main_loop_timer_progress_events)"
browser_main_loop_timer_progress_events="$(value_for "${flow_line}" browser_main_loop_timer_progress_events)"
native_tcg_timer_events="$(value_for "${flow_line}" native_tcg_timer_events)"
browser_tcg_timer_events="$(value_for "${flow_line}" browser_tcg_timer_events)"
native_tcg_timer_progress_events="$(value_for "${flow_line}" native_tcg_timer_progress_events)"
browser_tcg_timer_progress_events="$(value_for "${flow_line}" browser_tcg_timer_progress_events)"
pfifo_result="$(value_for "${pfifo_line}" result)"
pfifo_divergence="$(value_for "${pfifo_line}" divergence)"

loaded_result="${loaded_result:-unknown}"
loaded_reason="${loaded_reason:-none}"
section_map_result="${section_map_result:-unknown}"
native_actual_result="${native_actual_result:-unknown}"
native_actual_reason="${native_actual_reason:-unknown}"
native_actual_direct_entry_pc="${native_actual_direct_entry_pc:-unknown}"
native_actual_first_entry_cpu="${native_actual_first_entry_cpu:-unknown}"
native_actual_first_after_idle_edge="${native_actual_first_after_idle_edge:-unknown}"
native_actual_after_idle_cpu_interrupts="${native_actual_after_idle_cpu_interrupts:-unknown}"
native_handoff_result="${native_handoff_result:-unknown}"
native_handoff_state="${native_handoff_state:-unknown}"
native_handoff_boot_reason="${native_handoff_boot_reason:-unknown}"
native_handoff_short_animation="${native_handoff_short_animation:-unknown}"
native_handoff_native_reference="${native_handoff_native_reference:-unknown}"
native_handoff_stream_idle_eip="${native_handoff_stream_idle_eip:-unknown}"
native_handoff_stream_idle_interrupt="${native_handoff_stream_idle_interrupt:-unknown}"
native_handoff_after_idle_top_edge="${native_handoff_after_idle_top_edge:-unknown}"
native_handoff_after_idle_interrupts="${native_handoff_after_idle_interrupts:-unknown}"
iret_result="${iret_result:-unknown}"
iret_divergence="${iret_divergence:-unknown}"
loop_result="${loop_result:-unknown}"
loop_divergence="${loop_divergence:-unknown}"
after_idle_divergence="${after_idle_divergence:-unknown}"
after_idle_cpu_interrupt_divergence="${after_idle_cpu_interrupt_divergence:-unknown}"
memory_poll_result="${memory_poll_result:-unknown}"
memory_poll_divergence="${memory_poll_divergence:-unknown}"
shared_memory_poll_addr="${shared_memory_poll_addr:-unknown}"
native_shared_memory_poll_value="${native_shared_memory_poll_value:-unknown}"
browser_shared_memory_poll_value="${browser_shared_memory_poll_value:-unknown}"
shared_memory_poll_tick_unit="${shared_memory_poll_tick_unit:-unknown}"
native_shared_memory_poll_ticks="${native_shared_memory_poll_ticks:-unknown}"
browser_shared_memory_poll_ticks="${browser_shared_memory_poll_ticks:-unknown}"
shared_memory_poll_tick_delta="${shared_memory_poll_tick_delta:-unknown}"
shared_memory_poll_tick_relation="${shared_memory_poll_tick_relation:-unknown}"
native_main_loop_timer_memory_watch_samples="${native_main_loop_timer_memory_watch_samples:-unknown}"
browser_main_loop_timer_memory_watch_samples="${browser_main_loop_timer_memory_watch_samples:-unknown}"
native_main_loop_timer_max_memory_watch_value="${native_main_loop_timer_max_memory_watch_value:-unknown}"
browser_main_loop_timer_max_memory_watch_value="${browser_main_loop_timer_max_memory_watch_value:-unknown}"
native_main_loop_timer_max_memory_watch_ticks="${native_main_loop_timer_max_memory_watch_ticks:-unknown}"
browser_main_loop_timer_max_memory_watch_ticks="${browser_main_loop_timer_max_memory_watch_ticks:-unknown}"
native_main_loop_timer_last_memory_watch_value="${native_main_loop_timer_last_memory_watch_value:-unknown}"
browser_main_loop_timer_last_memory_watch_value="${browser_main_loop_timer_last_memory_watch_value:-unknown}"
native_main_loop_timer_last_memory_watch_ticks="${native_main_loop_timer_last_memory_watch_ticks:-unknown}"
browser_main_loop_timer_last_memory_watch_ticks="${browser_main_loop_timer_last_memory_watch_ticks:-unknown}"
native_post_service_top_edge="${native_post_service_top_edge:-unknown}"
browser_post_service_top_edge="${browser_post_service_top_edge:-unknown}"
watch_edge_result="${watch_edge_result:-unknown}"
watch_edge_divergence="${watch_edge_divergence:-unknown}"
watch_edge_pre_tick_delta="${watch_edge_pre_tick_delta:-unknown}"
watch_edge_post_tick_delta="${watch_edge_post_tick_delta:-unknown}"
watch_edge_block_delta_match="${watch_edge_block_delta_match:-unknown}"
native_watch_edge_pre_ticks="${native_watch_edge_pre_ticks:-unknown}"
browser_watch_edge_pre_ticks="${browser_watch_edge_pre_ticks:-unknown}"
native_watch_edge_post_ticks="${native_watch_edge_post_ticks:-unknown}"
browser_watch_edge_post_ticks="${browser_watch_edge_post_ticks:-unknown}"
native_watch_edge_block_delta_ticks="${native_watch_edge_block_delta_ticks:-unknown}"
browser_watch_edge_block_delta_ticks="${browser_watch_edge_block_delta_ticks:-unknown}"
native_watch_edge_pre_edge="${native_watch_edge_pre_edge:-unknown}"
browser_watch_edge_pre_edge="${browser_watch_edge_pre_edge:-unknown}"
native_watch_edge_post_edge="${native_watch_edge_post_edge:-unknown}"
browser_watch_edge_post_edge="${browser_watch_edge_post_edge:-unknown}"
pre_service_result="${pre_service_result:-unknown}"
pre_service_divergence="${pre_service_divergence:-unknown}"
pre_service_tick_delta="${pre_service_tick_delta:-unknown}"
pre_service_native_first_read_ticks="${pre_service_native_first_read_ticks:-unknown}"
pre_service_browser_first_read_ticks="${pre_service_browser_first_read_ticks:-unknown}"
pre_service_native_first_read_edge="${pre_service_native_first_read_edge:-unknown}"
pre_service_browser_first_read_edge="${pre_service_browser_first_read_edge:-unknown}"
pre_service_browser_timer_source="${pre_service_browser_timer_source:-unknown}"
pre_service_browser_timer_ticks="${pre_service_browser_timer_ticks:-unknown}"
pre_service_browser_read_before_write="${pre_service_browser_read_before_write:-unknown}"
pre_service_browser_write_delta="${pre_service_browser_write_delta:-unknown}"
pre_service_browser_service_eip="${pre_service_browser_service_eip:-unknown}"
memory_watch_timeline_result="${memory_watch_timeline_result:-unknown}"
memory_watch_timeline_divergence="${memory_watch_timeline_divergence:-unknown}"
memory_watch_timeline_shared_delta="${memory_watch_timeline_shared_delta:-unknown}"
native_watch_install="${native_watch_install:-unknown}"
browser_watch_install="${browser_watch_install:-unknown}"
native_watch_access_events="${native_watch_access_events:-unknown}"
browser_watch_access_events="${browser_watch_access_events:-unknown}"
native_watch_write_events="${native_watch_write_events:-unknown}"
browser_watch_write_events="${browser_watch_write_events:-unknown}"
native_first_watch_write_eip="${native_first_watch_write_eip:-unknown}"
browser_first_watch_write_eip="${browser_first_watch_write_eip:-unknown}"
native_first_watch_write_ticks="${native_first_watch_write_ticks:-unknown}"
browser_first_watch_write_ticks="${browser_first_watch_write_ticks:-unknown}"
native_first_watch_write_value="${native_first_watch_write_value:-unknown}"
browser_first_watch_write_value="${browser_first_watch_write_value:-unknown}"
browser_last_watch_write_value="${browser_last_watch_write_value:-unknown}"
browser_first_shared_poll_ticks="${browser_first_shared_poll_ticks:-unknown}"
native_first_shared_poll_ticks="${native_first_shared_poll_ticks:-unknown}"
headless_pump_result="${headless_pump_result:-unknown}"
headless_pump_divergence="${headless_pump_divergence:-unknown}"
headless_pump_host_ready_before_boundary="${headless_pump_host_ready_before_boundary:-unknown}"
headless_pump_timer_before_boundary="${headless_pump_timer_before_boundary:-unknown}"
headless_pump_timer_after_boundary="${headless_pump_timer_after_boundary:-unknown}"
headless_pump_first_timer_watch_zero="${headless_pump_first_timer_watch_zero:-unknown}"
headless_pump_first_memory_write_zero="${headless_pump_first_memory_write_zero:-unknown}"
headless_pump_first_host_ready_line="${headless_pump_first_host_ready_line:-unknown}"
headless_pump_boundary_line="${headless_pump_boundary_line:-unknown}"
headless_pump_first_timer_line="${headless_pump_first_timer_line:-unknown}"
headless_pump_first_timer_placement="${headless_pump_first_timer_placement:-unknown}"
flow_result="${flow_result:-unknown}"
flow_divergence="${flow_divergence:-unknown}"
flow_timer_divergence="${flow_timer_divergence:-unknown}"
flow_mismatch_index="${flow_mismatch_index:-unknown}"
native_main_loop_timer_events="${native_main_loop_timer_events:-unknown}"
browser_main_loop_timer_events="${browser_main_loop_timer_events:-unknown}"
native_main_loop_timer_sources="${native_main_loop_timer_sources:-unknown}"
browser_main_loop_timer_sources="${browser_main_loop_timer_sources:-unknown}"
native_main_loop_timer_progress_events="${native_main_loop_timer_progress_events:-unknown}"
browser_main_loop_timer_progress_events="${browser_main_loop_timer_progress_events:-unknown}"
native_tcg_timer_events="${native_tcg_timer_events:-unknown}"
browser_tcg_timer_events="${browser_tcg_timer_events:-unknown}"
native_tcg_timer_progress_events="${native_tcg_timer_progress_events:-unknown}"
browser_tcg_timer_progress_events="${browser_tcg_timer_progress_events:-unknown}"
pfifo_result="${pfifo_result:-unknown}"
pfifo_divergence="${pfifo_divergence:-unknown}"
native_xbe_executed="$(strict_xbe_executed_for "${native_log}" native-headless)"
if [ "${native_xbe_executed}" != "yes" ] &&
   [ "${native_proof_log}" != "${native_log}" ]; then
    native_xbe_executed="$(strict_xbe_executed_for "${native_proof_log}" native-headless)"
fi
browser_xbe_executed="$(strict_xbe_executed_for "${browser_log}" browser-runtime)"
native_xbe_detector_proof="$(detector_proof_for "${native_proof_log}" native-headless)"
browser_xbe_detector_proof="$(detector_proof_for "${browser_log}" browser-runtime)"

summary_result="pass"
summary_reason="current-boundary-summarized"
if [ "${loaded_result}" = "pass" ]; then
    b6_status="pass"
    current_boundary="b6-complete"
    next_action="run-completion-audit"
elif [ "${native_xbe_detector_proof}" != "pass" ]; then
    b6_status="fail"
    current_boundary="post-idle-post-service-cpu-flow"
    next_action="prove-native-xbe-executed-detector"
elif [ "${native_xbe_executed}" != "yes" ] ||
     [ "${native_actual_result}" != "pass" ]; then
    b6_status="fail"
    current_boundary="post-idle-post-service-cpu-flow"
    next_action="prove-native-actual-dashboard-execution"
else
    b6_status="fail"
    current_boundary="post-idle-post-service-cpu-flow"
    next_action="converge-browser-post-service-flow"
    if [ "${flow_timer_divergence}" = "browser-missing-main-loop-timer-progress" ]; then
        next_action="restore-browser-main-loop-timer-progress"
    fi
    if [ "${headless_pump_divergence}" = "host-ready-before-boundary-pump-after-boundary" ]; then
        next_action="converge-browser-ready-edge-pump-placement"
    fi
fi

if [ "${section_map_result}" != "pass" ] \
    || [ -z "${native_actual_line}" ] \
    || [ -z "${native_handoff_line}" ] \
    || [ "${native_handoff_result}" != "pass" ] \
    || [ "${iret_result}" != "pass" ] \
    || [ "${loop_result}" != "pass" ] \
    || [ "${memory_poll_result}" != "pass" ] \
    || [ "${watch_edge_result}" != "pass" ] \
    || [ "${pre_service_result}" != "pass" ] \
    || { [ -n "${native_memory_watch_log}" ] && [ "${memory_watch_timeline_result}" != "pass" ]; } \
    || [ "${headless_pump_result}" != "pass" ] \
    || [ "${flow_result}" != "pass" ]; then
    summary_result="fail"
    summary_reason="required-diagnostic-failed"
fi

printf 'B6_CURRENT_BOUNDARY_RESULT result=%s reason=%s b6=%s b6_reason=%s native_xbe_executed=%s browser_xbe_executed=%s native_xbe_detector_proof=%s browser_xbe_detector_proof=%s native_actual_execution=%s native_actual_reason=%s native_direct_entry_pc=%s native_first_entry_ready_cpu=%s native_first_after_idle_edge=%s native_after_idle_cpu_interrupt_nonzero=%s native_handoff=%s native_handoff_state=%s native_handoff_boot_reason=%s native_handoff_short_animation=%s native_handoff_native_reference=%s native_handoff_latest_stream_idle_eip=%s native_handoff_latest_stream_idle_cpu_interrupt=%s native_handoff_after_idle_top_edge=%s native_handoff_after_idle_cpu_interrupt_nonzero=%s section_map=%s iret=%s iret_divergence=%s post_command_loop=%s loop_divergence=%s after_idle_divergence=%s after_idle_cpu_interrupt_divergence=%s post_service_memory_poll=%s post_service_memory_poll_divergence=%s shared_memory_poll_addr=%s native_shared_memory_poll_value=%s browser_shared_memory_poll_value=%s shared_memory_poll_tick_unit=%s native_shared_memory_poll_ticks=%s browser_shared_memory_poll_ticks=%s shared_memory_poll_tick_delta=%s shared_memory_poll_tick_relation=%s native_main_loop_timer_memory_watch_samples=%s browser_main_loop_timer_memory_watch_samples=%s native_main_loop_timer_max_memory_watch_value=%s browser_main_loop_timer_max_memory_watch_value=%s native_main_loop_timer_max_memory_watch_ticks=%s browser_main_loop_timer_max_memory_watch_ticks=%s native_main_loop_timer_last_memory_watch_value=%s browser_main_loop_timer_last_memory_watch_value=%s native_main_loop_timer_last_memory_watch_ticks=%s browser_main_loop_timer_last_memory_watch_ticks=%s native_post_service_top_edge=%s browser_post_service_top_edge=%s post_service_watch_edge=%s post_service_watch_edge_divergence=%s watch_edge_pre_tick_delta=%s watch_edge_post_tick_delta=%s watch_edge_block_delta_match=%s native_watch_edge_pre_ticks=%s browser_watch_edge_pre_ticks=%s native_watch_edge_post_ticks=%s browser_watch_edge_post_ticks=%s native_watch_edge_block_delta_ticks=%s browser_watch_edge_block_delta_ticks=%s native_watch_edge_pre_edge=%s browser_watch_edge_pre_edge=%s native_watch_edge_post_edge=%s browser_watch_edge_post_edge=%s pre_service_tick_gap=%s pre_service_tick_gap_divergence=%s pre_service_first_watch_read_tick_delta=%s pre_service_native_first_watch_read_ticks=%s pre_service_browser_first_watch_read_ticks=%s pre_service_native_first_watch_read_edge=%s pre_service_browser_first_watch_read_edge=%s pre_service_browser_first_timer_source=%s pre_service_browser_first_timer_watch_ticks=%s pre_service_browser_first_watch_read_before_write=%s pre_service_browser_first_watch_write_delta_from_read=%s pre_service_browser_first_service_eip=%s memory_watch_timeline=%s memory_watch_timeline_divergence=%s memory_watch_timeline_shared_delta=%s native_watch_install=%s browser_watch_install=%s native_watch_access_events=%s browser_watch_access_events=%s native_watch_write_events=%s browser_watch_write_events=%s native_first_watch_write_eip=%s browser_first_watch_write_eip=%s native_first_watch_write_ticks=%s browser_first_watch_write_ticks=%s native_first_watch_write_value=%s browser_first_watch_write_value=%s browser_last_watch_write_value=%s native_first_shared_poll_ticks=%s browser_first_shared_poll_ticks=%s headless_pump=%s headless_pump_divergence=%s headless_pump_host_ready_before_boundary=%s headless_pump_timer_before_boundary=%s headless_pump_timer_after_boundary=%s headless_pump_first_timer_watch_zero=%s headless_pump_first_memory_write_zero=%s headless_pump_first_host_ready_line=%s headless_pump_boundary_line=%s headless_pump_first_timer_line=%s headless_pump_first_timer_placement=%s post_idle_flow=%s post_idle_flow_divergence=%s post_idle_timer_divergence=%s first_flow_mismatch_index=%s native_main_loop_timer_events=%s browser_main_loop_timer_events=%s native_main_loop_timer_sources=%s browser_main_loop_timer_sources=%s native_main_loop_timer_progress_events=%s browser_main_loop_timer_progress_events=%s native_tcg_timer_events=%s browser_tcg_timer_events=%s native_tcg_timer_progress_events=%s browser_tcg_timer_progress_events=%s pfifo_transition=%s pfifo_transition_divergence=%s current_boundary=%s next=%s native_log=%s native_proof_log=%s native_memory_watch_log=%s browser_log=%s\n' \
    "${summary_result}" \
    "${summary_reason}" \
    "${b6_status}" \
    "${loaded_reason}" \
    "${native_xbe_executed}" \
    "${browser_xbe_executed}" \
    "${native_xbe_detector_proof}" \
    "${browser_xbe_detector_proof}" \
    "${native_actual_result}" \
    "${native_actual_reason}" \
    "${native_actual_direct_entry_pc}" \
    "${native_actual_first_entry_cpu}" \
    "${native_actual_first_after_idle_edge}" \
    "${native_actual_after_idle_cpu_interrupts}" \
    "${native_handoff_result}" \
    "${native_handoff_state}" \
    "${native_handoff_boot_reason}" \
    "${native_handoff_short_animation}" \
    "${native_handoff_native_reference}" \
    "${native_handoff_stream_idle_eip}" \
    "${native_handoff_stream_idle_interrupt}" \
    "${native_handoff_after_idle_top_edge}" \
    "${native_handoff_after_idle_interrupts}" \
    "${section_map_result}" \
    "${iret_result}" \
    "${iret_divergence}" \
    "${loop_result}" \
    "${loop_divergence}" \
    "${after_idle_divergence}" \
    "${after_idle_cpu_interrupt_divergence}" \
    "${memory_poll_result}" \
    "${memory_poll_divergence}" \
    "${shared_memory_poll_addr}" \
    "${native_shared_memory_poll_value}" \
    "${browser_shared_memory_poll_value}" \
    "${shared_memory_poll_tick_unit}" \
    "${native_shared_memory_poll_ticks}" \
    "${browser_shared_memory_poll_ticks}" \
    "${shared_memory_poll_tick_delta}" \
    "${shared_memory_poll_tick_relation}" \
    "${native_main_loop_timer_memory_watch_samples}" \
    "${browser_main_loop_timer_memory_watch_samples}" \
    "${native_main_loop_timer_max_memory_watch_value}" \
    "${browser_main_loop_timer_max_memory_watch_value}" \
    "${native_main_loop_timer_max_memory_watch_ticks}" \
    "${browser_main_loop_timer_max_memory_watch_ticks}" \
    "${native_main_loop_timer_last_memory_watch_value}" \
    "${browser_main_loop_timer_last_memory_watch_value}" \
    "${native_main_loop_timer_last_memory_watch_ticks}" \
    "${browser_main_loop_timer_last_memory_watch_ticks}" \
    "${native_post_service_top_edge}" \
    "${browser_post_service_top_edge}" \
    "${watch_edge_result}" \
    "${watch_edge_divergence}" \
    "${watch_edge_pre_tick_delta}" \
    "${watch_edge_post_tick_delta}" \
    "${watch_edge_block_delta_match}" \
    "${native_watch_edge_pre_ticks}" \
    "${browser_watch_edge_pre_ticks}" \
    "${native_watch_edge_post_ticks}" \
    "${browser_watch_edge_post_ticks}" \
    "${native_watch_edge_block_delta_ticks}" \
    "${browser_watch_edge_block_delta_ticks}" \
    "${native_watch_edge_pre_edge}" \
    "${browser_watch_edge_pre_edge}" \
    "${native_watch_edge_post_edge}" \
    "${browser_watch_edge_post_edge}" \
    "${pre_service_result}" \
    "${pre_service_divergence}" \
    "${pre_service_tick_delta}" \
    "${pre_service_native_first_read_ticks}" \
    "${pre_service_browser_first_read_ticks}" \
    "${pre_service_native_first_read_edge}" \
    "${pre_service_browser_first_read_edge}" \
    "${pre_service_browser_timer_source}" \
    "${pre_service_browser_timer_ticks}" \
    "${pre_service_browser_read_before_write}" \
    "${pre_service_browser_write_delta}" \
    "${pre_service_browser_service_eip}" \
    "${memory_watch_timeline_result}" \
    "${memory_watch_timeline_divergence}" \
    "${memory_watch_timeline_shared_delta}" \
    "${native_watch_install}" \
    "${browser_watch_install}" \
    "${native_watch_access_events}" \
    "${browser_watch_access_events}" \
    "${native_watch_write_events}" \
    "${browser_watch_write_events}" \
    "${native_first_watch_write_eip}" \
    "${browser_first_watch_write_eip}" \
    "${native_first_watch_write_ticks}" \
    "${browser_first_watch_write_ticks}" \
    "${native_first_watch_write_value}" \
    "${browser_first_watch_write_value}" \
    "${browser_last_watch_write_value}" \
    "${native_first_shared_poll_ticks}" \
    "${browser_first_shared_poll_ticks}" \
    "${headless_pump_result}" \
    "${headless_pump_divergence}" \
    "${headless_pump_host_ready_before_boundary}" \
    "${headless_pump_timer_before_boundary}" \
    "${headless_pump_timer_after_boundary}" \
    "${headless_pump_first_timer_watch_zero}" \
    "${headless_pump_first_memory_write_zero}" \
    "${headless_pump_first_host_ready_line}" \
    "${headless_pump_boundary_line}" \
    "${headless_pump_first_timer_line}" \
    "${headless_pump_first_timer_placement}" \
    "${flow_result}" \
    "${flow_divergence}" \
    "${flow_timer_divergence}" \
    "${flow_mismatch_index}" \
    "${native_main_loop_timer_events}" \
    "${browser_main_loop_timer_events}" \
    "${native_main_loop_timer_sources}" \
    "${browser_main_loop_timer_sources}" \
    "${native_main_loop_timer_progress_events}" \
    "${browser_main_loop_timer_progress_events}" \
    "${native_tcg_timer_events}" \
    "${browser_tcg_timer_events}" \
    "${native_tcg_timer_progress_events}" \
    "${browser_tcg_timer_progress_events}" \
    "${pfifo_result}" \
    "${pfifo_divergence}" \
    "${current_boundary}" \
    "${next_action}" \
    "$(repo_relative_path "${native_log}")" \
    "$(repo_relative_path "${native_proof_log}")" \
    "${native_memory_watch_log:+$(repo_relative_path "${native_memory_watch_log}")}" \
    "$(repo_relative_path "${browser_log}")"
