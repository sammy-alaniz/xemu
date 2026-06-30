#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-memory-watch-timeline-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-memory-watch-timeline.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

native_log="${tmp_dir}/native.log"
browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 memory-watch-install context=native-headless result=pass phys=0x0003a890 watch_bytes=4 limit=64 mr=xbox.ram mr_offset=0x0003a890 source=entry-ready
BOOT_MARK b6 memory-watch context=native-headless seq=1 access=read phys=0x0003a890 watch_phys=0x0003a890 watch_bytes=4 value_read=yes value_phase=pre-access value=0x00149970 entry_ready=yes stream_idle=no nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise cpu_known=yes eip=0x80030e84 source=mem-access-callback
BOOT_MARK b6 memory-watch context=native-headless seq=2 access=write phys=0x0003a890 watch_phys=0x0003a890 watch_bytes=4 value_read=yes value_phase=pre-access value=0x00149970 entry_ready=yes stream_idle=no nv2a_wait_source=pcrtc nv2a_wait_op=vblank-raise cpu_known=yes eip=0x80030e84 source=mem-access-callback
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless observed_seq=1 start_pc=0x80030e84 next_pc=0x80030f31 eip=0x80030f31 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_phys=0x0003a890 start_mem_value=0x0014c080 next_mem_value_read=no
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=1 timer_progress=yes eip=0x8001b02f memory_watch_phys=0x0003a890 memory_watch_value_read=yes memory_watch_value=0x00002710
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x8001b02f next_pc=0x8001b030 eip=0x8001b030 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=no next_mem_value_read=yes next_mem_addr=0x8003a890 next_mem_phys=0x0003a890 next_mem_value=0x00002710
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=browser-behind result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'MEMORY_WATCH_TIMELINE_COMPARE result=pass' \
    'divergence=browser-shared-poll-before-watch-catchup' \
    'watch_phys=0x0003a890' \
    'watch_tick_unit=0x00002710' \
    'shared_poll_tick_relation=browser-behind' \
    'shared_poll_tick_delta=135' \
    'browser_timer_max_relation=browser-under-native-shared-poll' \
    'native_watch_install=pass' \
    'native_watch_write_events=1' \
    'native_first_watch_write_eip=0x80030e84' \
    'native_first_shared_poll_value=0x0014c080' \
    'native_first_shared_poll_ticks=136' \
    'browser_first_shared_poll_value=0x00002710' \
    'browser_first_shared_poll_ticks=1' \
    'browser_max_timer_watch_value=0x00002710' \
    'browser_max_timer_watch_ticks=1'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=browser-behind result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=browser-behind result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=1 timer_progress=yes eip=0x80030e84 memory_watch_phys=0x0003a890 memory_watch_value_read=yes memory_watch_value=0x0014c080
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=1 start_pc=0x80030e84 next_pc=0x80030f31 eip=0x80030f31 nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty start_mem_value_read=yes start_mem_addr=0x8003a890 start_mem_phys=0x0003a890 start_mem_value=0x0014c080 next_mem_value_read=no
EOF

if ! "${script}" --native-log "${native_log}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=shared-equal result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'divergence=shared-poll-equal' \
    'shared_poll_tick_relation=equal' \
    'shared_poll_tick_delta=0' \
    'browser_timer_max_relation=browser-reaches-native-shared-poll'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=shared-equal result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done

printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=shared-equal result=pass\n'

if "${script}" --native-log "${tmp_dir}/missing.log" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=missing-native result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'MEMORY_WATCH_TIMELINE_COMPARE result=fail' "${out_path}"; then
    printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=missing-native result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST case=missing-native result=pass\n'
printf 'MEMORY_WATCH_TIMELINE_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
