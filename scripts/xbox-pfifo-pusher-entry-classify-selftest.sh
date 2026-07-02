#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-pfifo-pusher-entry-classify.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pfifo-pusher-entry.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=175080 source=virtual-header
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready guest_entry=0x00017d60 source=virtual-header
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress wait_pfifo_known=no wait_fifo_access=no wait_dma_get=0x03880000 wait_dma_put=0x03880000
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=2 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress wait_pfifo_known=no wait_fifo_access=no wait_dma_get=0x03880000 wait_dma_put=0x03880000
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881300 push_access=yes pull_access=yes dma_push_access=yes dma_push_status=no fifo_access=yes waiting_flip=no waiting_nop=no waiting_context=no halt=no fifo_kick=no
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=2 op=pusher-new-method-inc dma_get=0x03880000 dma_put=0x03881300 push_access=yes pull_access=yes dma_push_access=yes dma_push_status=no fifo_access=yes waiting_flip=no waiting_nop=no waiting_context=no halt=no fifo_kick=no
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=after-opportunity result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_PUSHER_ENTRY_CLASSIFY result=pass' \
    'divergence=pusher-entry-after-opportunities' \
    'timer_opportunities=2' \
    'pusher_enter_events=1' \
    'explicit_not_entered_markers=0' \
    'xbe_loaded_line=1' \
    'entry_ready_line=2' \
    'marker_contract=pusher-skip-or-enter-after-xbe-loaded' \
    'previous_pusher_before_first_opportunity=no' \
    'last_pusher_not_entered_line=1' \
    'last_pusher_not_entered_source=static-marker-contract' \
    'last_pusher_not_entered_reason_before_first_opportunity=not-called-before-first-opportunity' \
    'first_pusher_enter_delta_from_last_opportunity=1' \
    'first_pusher_enter_reason=entry-gates-open-with-dma-pending' \
    'first_pusher_enter_pending_dma=yes' \
    'first_pusher_enter_dma_to_put=4864'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=after-opportunity result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=after-opportunity result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=175080 source=virtual-header
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-enter dma_get=0x03880000 dma_put=0x03881300 push_access=yes pull_access=yes dma_push_access=yes dma_push_status=no fifo_access=yes waiting_flip=no waiting_nop=no waiting_context=no halt=no fifo_kick=no
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pfifo-window wait_op=pusher-empty wait_pfifo_known=yes wait_fifo_access=yes wait_dma_get=0x03881318 wait_dma_put=0x03881318
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=before-opportunity result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'divergence=pusher-active-before-opportunities' \
    'previous_pusher_before_first_opportunity=yes' \
    'previous_pusher_line=2' \
    'last_pusher_not_entered_source=progress' \
    'last_pusher_not_entered_reason_before_first_opportunity=pusher-event-before-first-opportunity' \
    'first_pusher_enter_delta_from_first_opportunity=-1'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=before-opportunity result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=before-opportunity result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000 image_size=175080 source=virtual-header
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty wait_source=pcrtc wait_op=vblank-suppress wait_pfifo_known=no wait_fifo_access=no
BOOT_MARK b6 pfifo=progress context=browser-runtime seq=1 op=pusher-stall dma_get=0x03880000 dma_put=0x03881300 push_access=yes pull_access=yes dma_push_access=yes dma_push_status=no fifo_access=no waiting_flip=no waiting_nop=no waiting_context=no halt=no fifo_kick=no
EOF

if "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=missing-enter result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'PFIFO_PUSHER_ENTRY_CLASSIFY result=fail' \
    'divergence=missing-pusher-enter' \
    'first_pusher_enter_reason=missing-pusher-enter'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=missing-enter result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST case=missing-enter result=pass\n'

printf 'PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST_RESULT result=pass cases=3\n'
