#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pfifo-scheduler-state-classify.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pfifo-scheduler-classify.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_phys=0x000c7d60
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=1 op=idle-wait-before dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=no fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=2 op=kick kick_source=nv-user-dma-put dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=yes fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=3 op=idle-wait-after dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=yes fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=4 op=before-run-pusher dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=no fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881318
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=asleep result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_SCHEDULER_STATE_CLASSIFY result=pass' \
    'divergence=pfifo-thread-asleep-before-first-opportunity' \
    'loop_guard_field=pfifo_scheduler_state_before_first_timer_opportunity' \
    'scheduler_events_before_first_opportunity=1' \
    'kick_events_before_first_opportunity=0' \
    'wait_before_first_opportunity=1' \
    'before_run_pusher_before_first_opportunity=0' \
    'last_scheduler_before_first_opportunity_op=idle-wait-before' \
    'last_scheduler_before_first_opportunity_kick_source=none' \
    'first_scheduler_after_last_opportunity_op=kick' \
    'first_scheduler_after_last_opportunity_kick_source=nv-user-dma-put' \
    'kick_sources_before_first_opportunity=none' \
    'first_kick_after_last_opportunity_source=nv-user-dma-put' \
    'first_kick_after_last_opportunity_delta=1' \
    'first_before_run_pusher_after_last_opportunity_delta=3' \
    'scheduler_markers_present=yes'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=asleep result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=asleep result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_phys=0x000c7d60
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=1 op=idle-wait-before dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=no fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=2 op=kick kick_source=nv-user-dma-put dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=yes fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=scheduler context=browser-runtime seq=3 op=idle-wait-after dma_get=0x03880000 dma_put=0x03881318 dma_to_put=4888 halt=no fifo_kick=yes fifo_access=yes push_access=yes dma_push_access=yes dma_push_status=no
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=kick-no-wake result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_SCHEDULER_STATE_CLASSIFY result=pass' \
    'divergence=pfifo-kick-before-opportunity-without-thread-wake' \
    'scheduler_events_before_first_opportunity=2' \
    'kick_events_before_first_opportunity=1' \
    'wake_before_first_opportunity=0' \
    'last_scheduler_before_first_opportunity_op=kick' \
    'last_scheduler_before_first_opportunity_kick_source=nv-user-dma-put' \
    'kick_sources_before_first_opportunity=nv-user-dma-put' \
    'first_kick_after_last_opportunity_line=0' \
    'first_kick_after_last_opportunity_source=none' \
    'first_scheduler_after_last_opportunity_op=idle-wait-after'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=kick-no-wake result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=kick-no-wake result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_phys=0x000c7d60
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881318
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=missing-marker result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_SCHEDULER_STATE_CLASSIFY result=skip' \
    'divergence=missing-pfifo-scheduler-markers' \
    'scheduler_events=0' \
    'kick_sources_before_first_opportunity=none' \
    'scheduler_markers_present=no'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=missing-marker result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST case=missing-marker result=pass\n'

printf 'PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST_RESULT result=pass cases=3\n'
