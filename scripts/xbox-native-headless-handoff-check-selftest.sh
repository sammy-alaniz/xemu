#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-native-headless-handoff-check.py"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-native-headless-handoff.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

write_default_log() {
    cat >"${tmpdir}/default.log" <<'EOF'
Created QEMU launch parameters: ./qemu-system-i386 -machine xbox,bootrom=/xemu-fixtures/mcpx.bin,kernel-irqchip=off,avpack=hdtv -display none -audio none
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=native-headless result=pass guest_pc=0x00017d60 eip=0x80014703 phys_match=yes section_flags=0x00000006
BOOT_MARK b6 dashboard=xbe-exec-edge context=native-headless start_pc=0x80014703 next_pc=0x8001470a start_phys_match=no next_phys_match=no
BOOT_MARK b6 pfifo=stream-idle-boundary context=native-headless eip=0x8001b030 esp=0x800395f0 cpu_interrupt_request=0x00000000 pending_interrupt=no irq_inhibited=no last_transition_start_pc=0x8001b02f last_transition_next_pc=0x8001b030 dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless stream_idle=yes start_pc=0x800426d4 next_pc=0x800426de eip=0x800426de esp=0xd0025c28 cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 ac97=callback context=native-headless eip=0x8001b030
BOOT_SMOKE_RESULT reason=timeout elapsed_ms=60036 exit=0
EOF
}

write_short_animation_log() {
    cat >"${tmpdir}/short.log" <<'EOF'
Created QEMU launch parameters: ./qemu-system-i386 -machine xbox,bootrom=/xemu-fixtures/mcpx.bin,short-animation=on,kernel-irqchip=off,avpack=hdtv -display none -audio none
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=native-headless result=pass guest_pc=0x00017d60 eip=0x800143c8 phys_match=yes section_flags=0x00000006
BOOT_MARK b6 dashboard=xbe-exec-edge context=native-headless start_pc=0x80014386 next_pc=0x800143cc start_phys_match=no next_phys_match=no
BOOT_MARK b6 pfifo=stream-idle-boundary context=native-headless eip=0x8001b02f esp=0x800395f0 cpu_interrupt_request=0x00000002 pending_interrupt=yes irq_inhibited=yes last_transition_start_pc=0x8001b030 last_transition_next_pc=0x8001b02f dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless stream_idle=yes start_pc=0x80030e4c next_pc=0x80014f31 eip=0x80014f31 esp=0xd0025bd8 cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_SMOKE_RESULT reason=timeout elapsed_ms=90038 exit=0
EOF
}

write_executed_log() {
    cat >"${tmpdir}/executed.log" <<'EOF'
Created QEMU launch parameters: ./qemu-system-i386 -machine xbox,bootrom=/xemu-fixtures/mcpx.bin,kernel-irqchip=off,avpack=hdtv -display none -audio none
BOOT_MARK b6 dashboard=xbe-entry-probe context=native-headless status=ready guest_entry=0x00017d60 entry_code_read=yes phys_match=yes
BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=native-headless result=pass guest_pc=0x00017d60 eip=0x80014703 phys_match=yes section_flags=0x00000006
BOOT_MARK b6 dashboard=xbe-executed context=native-headless guest_pc=0x00017d60 phys_match=yes section_flags=0x00000006
NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless dashboard=xbe-executed hash=abc
BOOT_SMOKE_RESULT reason=completed elapsed_ms=30000 exit=0
EOF
}

assert_output() {
    local name="$1"
    local expected_status="$2"
    local pattern="$3"
    shift 3
    local output
    local status

    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if [ "${status}" -ne "${expected_status}" ]; then
        printf 'NATIVE_HEADLESS_HANDOFF_SELFTEST result=fail case=%s reason=bad-status expected=%s actual=%s output=%s\n' \
            "${name}" "${expected_status}" "${status}" "${output}" >&2
        exit 1
    fi

    if ! printf '%s' "${output}" | grep -Eq "${pattern}"; then
        printf 'NATIVE_HEADLESS_HANDOFF_SELFTEST result=fail case=%s reason=bad-output pattern=%s output=%s\n' \
            "${name}" "${pattern}" "${output}" >&2
        exit 1
    fi
}

write_default_log
write_short_animation_log
write_executed_log

assert_output default 0 \
    'result=pass .*terminal_state=native-headless-timeout-after-stream-idle .*actual_xbe_executed=no .*latest_stream_idle_eip=0x8001b030 .*short_animation=no' \
    "${script}" "${tmpdir}/default.log"

assert_output executed 0 \
    'result=pass .*terminal_state=dashboard-executed-with-native-reference .*actual_xbe_executed=yes .*native_reference=pass .*direct_entry_pc=yes' \
    "${script}" "${tmpdir}/executed.log"

assert_output compare 0 \
    'NATIVE_HEADLESS_HANDOFF_COMPARE result=pass .*same_terminal_state=yes .*compare_short_animation=yes .*short_animation_changed=yes' \
    "${script}" "${tmpdir}/default.log" \
        --compare-log "${tmpdir}/short.log" \
        --compare-label short-animation

printf 'NATIVE_HEADLESS_HANDOFF_SELFTEST result=pass cases=3\n'
