#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pre-service-tick-gap-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pre-service-tick-gap.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no pmc_pending=0x01000000 pcrtc_pending=0x00000001 last_transition_start_pc=0x80030e4c last_transition_next_pc=0x80014f5f
BOOT_MARK b6 pfifo=stream-idle-boundary context=native-headless eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 main-loop=timers context=native-headless source=main-loop-wait seq=1 timer_progress=yes eip=0x80014f5f cpu_interrupt_request=0x00000000 virtual_now_before=1000 virtual_deadline_before=0 virtual_has_timers_before=yes virtual_expired_before=yes virtual_now_after=2000 virtual_deadline_after=1000 virtual_has_timers_after=yes virtual_expired_after=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 start_pc=0x80014f5f next_pc=0x80030e84 eip=0x80030e84 cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_op=pusher-empty nv2a_pmc_pending=0x01000000 nv2a_pcrtc_pending=0x00000001 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x0014c080 start_mem_value_read=no
BOOT_MARK b6 memory-watch context=native-headless seq=1 access=write phys=0x0003a890 watch_phys=0x0003a890 value_read=yes value=0x0014c080 eip=0x80030e84
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime eip=0x8001b030 cpu_interrupt_request=0x00000000 pending_interrupt=no pmc_pending=0x00000000 pcrtc_pending=0x00000000 last_transition_start_pc=0x8001b02f last_transition_next_pc=0x8001b030
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-ready-edge-qemu-pump seq=1 timer_progress=yes eip=0x8001b02f cpu_interrupt_request=0x00000002 virtual_now_before=3000 virtual_deadline_before=0 virtual_has_timers_before=yes virtual_expired_before=yes virtual_now_after=3000 virtual_deadline_after=1000 virtual_has_timers_after=yes virtual_expired_after=no memory_watch_value_read=yes memory_watch_value=0x00000000
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime eip=0x8001b02f cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80014f32 next_pc=0x80030e84 eip=0x80030e84 cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_op=pusher-empty nv2a_pmc_pending=0x00000000 nv2a_pcrtc_pending=0x00000000 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x00000000 start_mem_value_read=no
BOOT_MARK b6 memory-watch context=browser-runtime seq=1 access=write phys=0x0003a890 watch_phys=0x0003a890 value_read=yes value=0x00000000 eip=0x80030e84
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime phase=before intno=0x30 eip=0x80030e84
BOOT_MARK b6 cpu=iret context=browser-runtime phase=after eip=0x80030e84
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=browser-behind result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'PRE_SERVICE_TICK_GAP_COMPARE result=pass' \
    'divergence=browser-first-watch-read-before-catchup' \
    'watch_phys=0x0003a890' \
    'tick_unit=0x00002710' \
    'first_watch_read_tick_delta=136' \
    'native_first_watch_read_ticks=136' \
    'browser_first_watch_read_ticks=0' \
    'browser_first_timer_source=browser-ready-edge-qemu-pump' \
    'browser_first_timer_virtual_deadline_before=0' \
    'browser_first_timer_virtual_expired_before=yes' \
    'browser_first_timer_virtual_advance_ns=0' \
    'browser_first_timer_watch_ticks=0' \
    'browser_first_timer_delta_to_read=2' \
    'browser_first_service_before_read=no' \
    'browser_first_service_delta_to_read=-2' \
    'browser_first_watch_write_before_read=no' \
    'browser_first_watch_read_before_write=yes'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=browser-behind result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=browser-behind result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 main-loop=timers context=browser-runtime source=main-loop-wait seq=1 timer_progress=yes eip=0x80014f5f cpu_interrupt_request=0x00000000 virtual_now_before=1000 virtual_deadline_before=0 virtual_has_timers_before=yes virtual_expired_before=yes virtual_now_after=2000 virtual_deadline_after=1000 virtual_has_timers_after=yes virtual_expired_after=no memory_watch_value_read=yes memory_watch_value=0x0014c080
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80014f5f next_pc=0x80030e84 eip=0x80030e84 cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_op=pusher-empty next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x0014c080 start_mem_value_read=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=equal result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'divergence=first-watch-read-equal' "${out_path}"; then
    printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=equal result=fail reason=missing-equal\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=equal result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'PRE_SERVICE_TICK_GAP_COMPARE result=fail reason=missing-native-log' "${out_path}"; then
    printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'PRE_SERVICE_TICK_GAP_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
