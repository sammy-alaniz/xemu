#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-idle-before-pfifo-transition-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xbox-idle-before-pfifo-transition-compare.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

run_case() {
    local name="$1"
    local expected="$2"
    local native_log="${tmp_dir}/${name}.native.log"
    local browser_log="${tmp_dir}/${name}.browser.log"
    shift 2

    "$@" "${native_log}" "${browser_log}"
    output="$("${script}" --native-log "${native_log}" --browser-log "${browser_log}")"
    case "${output}" in
        *"${expected}"*) ;;
        *)
            printf 'SELFTEST_FAIL case=%s expected=%s output=%s\n' \
                "${name}" "${expected}" "${output}" >&2
            exit 1
            ;;
    esac
}

write_browser_only() {
    local native_log="$1"
    local browser_log="$2"
    printf 'BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless\n' >"${native_log}"
    cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 cpu=idle-before-pfifo-transition context=browser-runtime seq=1 observed_tbs=5180 source=tcg-tb-post pfifo_transition_seen=no loop_kind=fallthrough edge_hits=1 start_pc=0x8001b02f next_pc=0x8001b030 tb_size=1 tb_exit=0 expected_next=0x8001b030 fallthrough_match=yes cpu_known=yes cpu_mode=protected32 cpl=0 eip=0x8001b030 cs=0x0008 esp=0x800395f0 eflags=0x00000246 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 pending_interrupt=no cpu_halted=no cpu_exit_request=no cpu_exception_index=-1 nv2a_wait_present=yes nv2a_wait_generation=994 nv2a_wait_source=pfifo-window nv2a_wait_op=puller-method-done nv2a_wait_seq=373 nv2a_method=0x1d90 nv2a_parameter=0x00000000 nv2a_dma_get=0x0388130c nv2a_dma_put=0x03881318 nv2a_dma_to_put=12 nv2a_dma_state_method=0x1d90 nv2a_dma_state_count=1
EOF
}

write_both_missing() {
    local native_log="$1"
    local browser_log="$2"
    printf 'BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless\n' >"${native_log}"
    printf 'BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime\n' >"${browser_log}"
}

write_both_present_mismatch() {
    local native_log="$1"
    local browser_log="$2"
    cat >"${native_log}" <<'EOF'
BOOT_MARK b6 cpu=idle-before-pfifo-transition context=native-headless seq=1 start_pc=0x80018c8e next_pc=0x80018c95 eip=0x80018c95 pfifo_transition_seen=no nv2a_wait_source=pfifo-window nv2a_wait_op=puller-method-done nv2a_wait_seq=1 nv2a_dma_get=0x0388130c nv2a_dma_put=0x03881318 nv2a_dma_to_put=12 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000
EOF
    cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 cpu=idle-before-pfifo-transition context=browser-runtime seq=1 start_pc=0x8001b02f next_pc=0x8001b030 eip=0x8001b030 pfifo_transition_seen=no nv2a_wait_source=pfifo-window nv2a_wait_op=puller-method-done nv2a_wait_seq=373 nv2a_dma_get=0x0388130c nv2a_dma_put=0x03881318 nv2a_dma_to_put=12 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000
EOF
}

run_case browser-only \
    'divergence=browser-idle-before-transition-only native_marker=missing browser_marker=present' \
    write_browser_only
run_case both-missing \
    'divergence=both-missing native_marker=missing browser_marker=missing' \
    write_both_missing
run_case both-present-mismatch \
    'divergence=idle-before-transition-mismatch native_marker=present browser_marker=present' \
    write_both_present_mismatch

printf 'IDLE_BEFORE_PFIFO_TRANSITION_COMPARE_SELFTEST result=pass\n'
