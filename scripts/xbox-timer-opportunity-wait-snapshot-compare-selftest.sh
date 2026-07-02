#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-timer-opportunity-wait-snapshot-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-timer-opportunity-wait.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

browser_log="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty virtual_expired=yes eip=0x8002430e memory_watch_value=0x00000000 wait_source=pcrtc wait_op=vblank-suppress pfifo_empty_blocker=wait-source-not-pfifo-window
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-new-method-inc dma_get=0x03880e00 dma_put=0x03881318 available=326
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-after result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_COMPARE result=pass' \
    'divergence=no-pfifo-window-published-before-opportunities' \
    'timer_opportunities=1' \
    'pfifo_window_publications=1' \
    'opportunities_with_previous_pfifo=0' \
    'opportunities_with_next_pfifo=1' \
    'opportunity_wait_sources=pcrtc' \
    'opportunity_blockers=wait-source-not-pfifo-window' \
    'first_previous_pfifo_line=0' \
    'first_next_pfifo_line=2' \
    'first_next_pfifo_delta=1'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-after result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-after result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=puller-method dma_get=0x03880e04 dma_put=0x03881318 available=1
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=no reason=wait-not-pfifo-empty virtual_expired=yes eip=0x8002430e memory_watch_value=0x00000000 wait_source=pcrtc wait_op=vblank-suppress pfifo_empty_blocker=wait-source-not-pfifo-window
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-before-not-selected result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'divergence=pfifo-window-published-but-not-selected' \
    'opportunities_with_previous_pfifo=1' \
    'opportunities_with_next_pfifo=0' \
    'first_previous_pfifo_line=1' \
    'first_previous_pfifo_delta=1' \
    'first_next_pfifo_line=0'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-before-not-selected result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=pfifo-before-not-selected result=pass\n'

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=1 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318 available=0
BOOT_MARK b6 headless=timer-opportunity context=browser-runtime seq=1 ready=yes reason=ready virtual_expired=yes eip=0x8001b02f memory_watch_value=0x00002710 wait_source=pfifo-window wait_op=pusher-empty pfifo_empty_blocker=none
EOF

if ! "${script}" --browser-log "${browser_log}" >"${out_path}" 2>&1; then
    printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=selected-pfifo-empty result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
for pattern in \
    'divergence=selected-pfifo-window-empty' \
    'opportunity_wait_sources=pfifo-window' \
    'opportunity_wait_ops=pusher-empty' \
    'opportunity_ready=1' \
    'first_opportunity_watch_value=0x00002710'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=selected-pfifo-empty result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST case=selected-pfifo-empty result=pass\n'
printf 'TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST_RESULT result=pass cases=3\n'
