#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
script="${repo_root}/scripts/xbox-headless-pump-placement-compare.py"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-headless-pump-placement.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

log_path="${tmp_dir}/browser.log"
out_path="${tmp_dir}/out.log"

cat >"${log_path}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 eip=0x8003001b cpu_interrupt_request=0x00000000
BOOT_MARK b6 headless=timer-pump-gate context=browser-runtime seq=3 mode=pfifo-before-transition-activity-then-after-pfifo-empty ready=yes reason=ready transition_seen=no eip=0x8003001b cpu_interrupt_request=0x00000000 wait_op=puller-method-done wait_dma_to_put=4
BOOT_MARK b6 headless=timer-pump-gate context=browser-runtime seq=885 entry_ready=yes pump_ready=yes
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime seq=1 eip=0x8003e61e cpu_interrupt_request=0x00000000
BOOT_MARK b6 headless=timer-pump-step context=browser-runtime seq=1 phase=before progress=no
BOOT_MARK b6 headless=timer-pump-step context=browser-runtime seq=2 phase=after progress=yes
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=1 timer_progress=yes eip=0x80019db5 cpu_interrupt_request=0x00000002 memory_watch_value=0x00000000 memory_watch_value_read=yes nv2a_wait_op=pusher-empty
BOOT_MARK b6 memory-watch context=browser-runtime seq=1 access=write value=0x00000000 eip=0x80030e84
EOF

if ! "${script}" --browser-log "${log_path}" >"${out_path}" 2>&1; then
    printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missed-window result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'HEADLESS_PUMP_PLACEMENT_COMPARE result=pass' \
    'divergence=host-ready-before-boundary-pump-after-boundary' \
    'host_ready_before_boundary=yes' \
    'timer_after_boundary=yes' \
    'first_timer_watch_zero=yes' \
    'first_memory_write_zero=yes'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missed-window result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missed-window result=pass\n'

cat >"${log_path}" <<'EOF'
BOOT_MARK b6 headless=timer-pump-gate context=browser-runtime seq=3 mode=pfifo-before-transition-activity-then-after-pfifo-empty ready=yes reason=ready transition_seen=no eip=0x8003001b cpu_interrupt_request=0x00000000 wait_op=puller-method-done wait_dma_to_put=4
BOOT_MARK b6 headless=timer-pump-gate context=browser-runtime seq=885 entry_ready=yes pump_ready=yes
BOOT_MARK b6 headless=timer-pump-step context=browser-runtime seq=1 phase=after progress=yes
BOOT_MARK b6 main-loop=timers context=browser-runtime source=browser-headless-host-pump-bounded seq=1 timer_progress=yes eip=0x8003001b cpu_interrupt_request=0x00000002 memory_watch_value=0x00002710 memory_watch_value_read=yes nv2a_wait_op=puller-method-done
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 eip=0x8003001b cpu_interrupt_request=0x00000002
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime seq=1 eip=0x8003e61e cpu_interrupt_request=0x00000002
EOF

if ! "${script}" --browser-log "${log_path}" >"${out_path}" 2>&1; then
    printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=pretransition-pump result=fail reason=unexpected-status\n' >&2
    cat "${out_path}" >&2
    exit 1
fi

for pattern in \
    'divergence=pump-before-stream-idle-transition' \
    'timer_before_boundary=yes' \
    'timer_after_boundary=no' \
    'first_timer_watch_zero=no'; do
    if ! grep -q "${pattern}" "${out_path}"; then
        printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=pretransition-pump result=fail reason=missing-pattern pattern=%s\n' "${pattern}" >&2
        cat "${out_path}" >&2
        exit 1
    fi
done
printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=pretransition-pump result=pass\n'

cat >"${log_path}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 eip=0x8003001b
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime seq=1 eip=0x8003e61e
EOF

if "${script}" --browser-log "${log_path}" >"${out_path}" 2>&1; then
    printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missing-ready result=fail reason=unexpected-pass\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
if ! grep -q 'divergence=missing-ready-gate' "${out_path}"; then
    printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missing-ready result=fail reason=missing-fail\n' >&2
    cat "${out_path}" >&2
    exit 1
fi
printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST case=missing-ready result=pass\n'
printf 'HEADLESS_PUMP_PLACEMENT_COMPARE_SELFTEST_RESULT result=pass cases=3\n'
