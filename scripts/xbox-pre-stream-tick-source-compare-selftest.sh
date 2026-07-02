#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pre-stream-tick-source-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pre-stream-tick-source.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pit=irq-timer context=native-headless seq=1 irq_level=1 eip=0x800143c8 cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 main-loop=timers context=native-headless source=main-loop-wait seq=1 timer_progress=yes eip=0x800143c8 cpu_interrupt_request=0x00000002 memory_watch_value_read=yes memory_watch_value=0x00000000
BOOT_MARK b6 cpu=hard-irq context=native-headless op=set eip=0x800143c8 request_before=0x00000000 request_after=0x00000002
BOOT_MARK b6 pic=irq-ack context=native-headless intno=0x30 guest_irq=0 eip=0x80031ffa
BOOT_MARK b6 cpu=hard-irq-service context=native-headless phase=before intno=0x30 eip=0x80031ffa
BOOT_MARK b6 cpu=iret context=native-headless phase=after eip=0x80030e4c
BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 start_pc=0x80014f5f next_pc=0x80030e84 eip=0x80030e84 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x0014c080 start_mem_value_read=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 source=headless-poll ready=no reason=wait-not-pfifo-empty entry_ready=yes transition_seen=no progress_events=0 progress_limit=4 virtual_now=1000 virtual_deadline=900 virtual_deadline_delta=-100 virtual_has_timers=yes virtual_expired=yes eip=0x8001b02f cpu_interrupt_request=0x00000000 wait_source=pcrtc wait_op=vblank-suppress pfifo_empty_blocker=wait-source-not-pfifo-window memory_watch_value_read=yes memory_watch_value=0x00000000
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-ready-edge-qemu-pump seq=1 timer_progress=yes eip=0x8001b02f cpu_interrupt_request=0x00000002 memory_watch_value_read=yes memory_watch_value=0x00000000
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime eip=0x8001b030 cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime phase=before intno=0x30 eip=0x8001b030
BOOT_MARK b6 cpu=iret context=browser-runtime phase=after eip=0x80030e4c
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80014f32 next_pc=0x80030e84 eip=0x80030e84 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x00000000 start_mem_value_read=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=browser-lacks-service result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'PRE_STREAM_TICK_SOURCE_COMPARE result=pass' \
    'divergence=browser-lacks-pre-stream-vector-service' \
    'first_watch_read_tick_delta=136' \
    'native_pre_stream_pit_rising=1' \
    'native_pre_stream_timer_progress=1' \
    'native_pre_stream_pic_ack30=1' \
    'native_pre_stream_service30=1' \
    'native_pre_stream_iret_after=1' \
    'browser_pre_stream_timer_opportunities=1' \
    'browser_pre_stream_timer_opportunity_ready=0' \
    'browser_pre_stream_timer_opportunity_expired=1' \
    'browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty' \
    'browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window' \
    'browser_first_pre_opportunity_reason=wait-not-pfifo-empty' \
    'browser_first_pre_opportunity_wait_source=pcrtc' \
    'browser_first_pre_opportunity_pfifo_empty_blocker=wait-source-not-pfifo-window' \
    'browser_first_pre_opportunity_virtual_expired=yes' \
    'browser_first_pre_opportunity_deadline_delta=-100' \
    'browser_first_pre_opportunity_watch_ticks=0' \
    'browser_pre_stream_service30=0' \
    'browser_post_stream_service30=1' \
    'native_first_watch_read_ticks=136' \
    'browser_first_watch_read_ticks=0'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=browser-lacks-service result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=browser-lacks-service result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pit=irq-timer context=browser-runtime seq=1 irq_level=1 eip=0x800143c8 cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 source=headless-poll ready=yes reason=ready entry_ready=yes transition_seen=no progress_events=0 progress_limit=4 virtual_now=1000 virtual_deadline=900 virtual_deadline_delta=-100 virtual_has_timers=yes virtual_expired=yes eip=0x800143c8 cpu_interrupt_request=0x00000002 wait_source=pfifo-window wait_op=pusher-empty pfifo_empty_blocker=none memory_watch_value_read=yes memory_watch_value=0x0014c080
BOOT_MARK b6 main-loop=timers context=browser-runtime source=main-loop-wait seq=1 timer_progress=yes eip=0x800143c8 cpu_interrupt_request=0x00000002 memory_watch_value_read=yes memory_watch_value=0x00000000
BOOT_MARK b6 pic=irq-ack context=browser-runtime intno=0x30 guest_irq=0 eip=0x80031ffa
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime phase=before intno=0x30 eip=0x80031ffa
BOOT_MARK b6 cpu=iret context=browser-runtime phase=after eip=0x80030e4c
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime eip=0x80014f5f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80014f5f next_pc=0x80030e84 eip=0x80030e84 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x0014c080 start_mem_value_read=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=aligned result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'divergence=pre-stream-tick-source-aligned' "${out_path}"; then
    printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=aligned result=fail reason=missing-aligned\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=aligned result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80014f5f next_pc=0x80030e84 eip=0x80030e84 next_mem_value_read=yes next_mem_phys=0x0003a890 next_mem_addr=0x8003a890 next_mem_value=0x0014c080 start_mem_value_read=no
EOF

if "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=missing-transition result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'divergence=missing-stream-idle-transition' "${out_path}"; then
    printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=missing-transition result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST case=missing-transition result=pass\n'
printf 'PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
