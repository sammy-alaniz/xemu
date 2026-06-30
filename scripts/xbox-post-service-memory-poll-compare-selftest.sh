#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-post-service-memory-poll-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-post-service-memory-poll.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=native-headless seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 cpu=iret context=native-headless seq=2 phase=after eip=0x80030e84 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 loop_kind=forward start_pc=0x80030e84 next_pc=0x80030f31 tb_size=111 tb_exit=0 interrupts_enabled=yes cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=no next_mem_value_read=no next_mem_region=none
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 wait_op=pusher-empty-transition
BOOT_MARK b6 pfifo=window context=browser-runtime seq=2 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 cpu=iret context=browser-runtime seq=2 phase=after eip=0x80030e84 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 loop_kind=self start_pc=0x80031ffa next_pc=0x80031ffa tb_size=7 tb_exit=0 interrupts_enabled=yes cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_source=pgraph nv2a_wait_op=intr-enable start_mem_value_read=yes start_mem_kind=mov-r32-rm32 start_mem_addr=0xd001c938 start_mem_region=kernel-virtual-ram start_mem_phys=0x00078938 start_mem_value=0x00000000 next_mem_value_read=yes next_mem_kind=mov-r32-rm32 next_mem_addr=0xd001c938 next_mem_region=kernel-virtual-ram next_mem_phys=0x00078938 next_mem_value=0x00000000
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=memory-poll result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'POST_SERVICE_MEMORY_POLL_COMPARE result=pass' \
    'divergence=browser-memory-poll-mismatch' \
    'native_stream_idle_count=1' \
    'browser_stream_idle_count=2' \
    'native_preferred_iret_eip=0x80030e84' \
    'browser_preferred_iret_eip=0x80030e84' \
    'native_first_loop_after_iret=0x80030e84->0x80030f31' \
    'browser_first_loop_after_iret=0x80031ffa->0x80031ffa' \
    'native_top_edge=0x80030e84->0x80030f31' \
    'browser_top_edge=0x80031ffa->0x80031ffa' \
    'browser_top_wait_source=pgraph' \
    'browser_top_wait_op=intr-enable' \
    'browser_memory_poll_samples=1' \
    'browser_top_memory_poll_addr=0xd001c938' \
    'browser_top_memory_poll_region=kernel-virtual-ram'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=memory-poll result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=memory-poll result=pass\n'

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=native-headless seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 cpu=iret context=native-headless seq=2 phase=after eip=0x80030e84 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty
BOOT_MARK b6 main-loop=timers context=native-headless source=main-loop-wait seq=1 timer_progress=yes memory_watch_value_read=yes memory_watch_value=0x0014c080
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 loop_kind=forward start_pc=0x80030e84 next_pc=0x80030f31 tb_size=111 tb_exit=0 interrupts_enabled=yes cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=no next_mem_value_read=yes next_mem_kind=mov-r32-rm32 next_mem_addr=0x8003a890 next_mem_region=kernel-ram-alias next_mem_phys=0x0003a890 next_mem_value=0x0014c080
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 cpu=iret context=browser-runtime seq=2 phase=after eip=0x80030e84 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=1 timer_progress=yes memory_watch_value_read=yes memory_watch_value=0x00002710
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=2 timer_progress=yes memory_watch_value_read=yes memory_watch_value=0x00004e20
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 loop_kind=forward start_pc=0x80030e84 next_pc=0x80030f31 tb_size=111 tb_exit=0 interrupts_enabled=yes cpu_interrupt_request=0x00000000 pending_interrupt=no nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=no next_mem_value_read=yes next_mem_kind=mov-r32-rm32 next_mem_addr=0x8003a890 next_mem_region=kernel-ram-alias next_mem_phys=0x0003a890 next_mem_value=0x00002710
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=shared-tick-delta result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'divergence=shared-memory-poll-value-mismatch' \
    'shared_memory_poll_addr=0x8003a890' \
    'native_shared_memory_poll_value=0x0014c080' \
    'browser_shared_memory_poll_value=0x00002710' \
    'shared_memory_poll_tick_unit=0x00002710' \
    'native_shared_memory_poll_ticks=136' \
    'browser_shared_memory_poll_ticks=1' \
    'shared_memory_poll_tick_delta=135' \
    'shared_memory_poll_tick_relation=browser-behind' \
    'native_main_loop_timer_events=1' \
    'native_main_loop_timer_progress_events=1' \
    'native_main_loop_timer_max_memory_watch_value=0x0014c080' \
    'native_main_loop_timer_max_memory_watch_ticks=136' \
    'browser_main_loop_timer_events=2' \
    'browser_main_loop_timer_progress_events=2' \
    'browser_main_loop_timer_max_memory_watch_value=0x00004e20' \
    'browser_main_loop_timer_max_memory_watch_ticks=2' \
    'browser_main_loop_timer_last_memory_watch_value=0x00004e20' \
    'browser_main_loop_timer_last_memory_watch_ticks=2'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=shared-tick-delta result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=shared-tick-delta result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'POST_SERVICE_MEMORY_POLL_COMPARE result=fail' "${out_path}"; then
    printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'POST_SERVICE_MEMORY_POLL_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
