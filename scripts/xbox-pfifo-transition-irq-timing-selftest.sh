#!/usr/bin/env bash

set -euo pipefail

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/xemu-pfifo-transition-irq.XXXXXX")"
trap 'rm -rf "${tmpdir}"' EXIT

native_log="${tmpdir}/native.log"
browser_log="${tmpdir}/browser.log"

cat >"${native_log}" <<'EOF'
BOOT_MARK b6 cpu=hard-irq context=native-headless seq=1 op=set mask=0x00000002 request_before=0x00000000 request_after=0x00000002 eip=0x8001b02f
BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless seq=1 dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 cpu_known=yes eip=0x8001b02f cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 cpu=hard-irq context=native-headless seq=2 op=reset mask=0x00000102 request_before=0x00000002 request_after=0x00000000 eip=0x8001b030
BOOT_MARK b6 pic=irq-ack context=native-headless seq=1 intno=0x30 guest_irq=0 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq-service context=native-headless seq=1 phase=before intno=0x30 eip=0x8001b030 cpu_interrupt_request=0x00000000 stack_hash=0x1111
BOOT_MARK b6 main-loop=timers context=native-headless seq=1 timer_progress=yes eip=0x8001b030 cpu_interrupt_request=0x00000002
EOF

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 cpu_known=yes eip=0x8001b02f cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 pit=irq-timer context=browser-runtime seq=1 irq_level=1 eip=0x8001b030 cpu_interrupt_request=0x00000000 pending_interrupt=no
BOOT_MARK b6 tcg=timer-pump context=browser-runtime seq=1 mode=pit-after-pfifo-transition timer_progress=yes eip=0x8001b030 cpu_interrupt_request=0x00000000
BOOT_MARK b6 cpu=hard-irq context=browser-runtime seq=1 op=set mask=0x00000002 request_before=0x00000000 request_after=0x00000002 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq context=browser-runtime seq=2 op=reset mask=0x00000102 request_before=0x00000002 request_after=0x00000000 eip=0x8001b030
BOOT_MARK b6 pic=irq-ack context=browser-runtime seq=1 intno=0x30 guest_irq=0 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=1 phase=before intno=0x30 eip=0x8001b030 cpu_interrupt_request=0x00000000 stack_hash=0x1111
EOF

out="$(python3 scripts/xbox-pfifo-transition-irq-timing.py \
    --native-log "${native_log}" \
    --browser-log "${browser_log}")"

case "${out}" in
    *"result=pass"*"divergence=transition-pending-irq-mismatch"*"native_transition_irq=0x00000002"*"browser_transition_irq=0x00000000"*) ;;
    *)
        printf 'Expected transition pending IRQ mismatch, got:\n%s\n' "${out}" >&2
        exit 1
        ;;
esac

cat >"${browser_log}" <<'EOF'
BOOT_MARK b6 cpu=hard-irq context=browser-runtime seq=1 op=set mask=0x00000002 request_before=0x00000000 request_after=0x00000002 eip=0x8001b02f
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 cpu_known=yes eip=0x8001b02f cpu_interrupt_request=0x00000002 pending_interrupt=yes
BOOT_MARK b6 cpu=hard-irq context=browser-runtime seq=2 op=reset mask=0x00000102 request_before=0x00000002 request_after=0x00000000 eip=0x8001b030
BOOT_MARK b6 pic=irq-ack context=browser-runtime seq=1 intno=0x30 guest_irq=0 eip=0x8001b030
BOOT_MARK b6 cpu=hard-irq-service context=browser-runtime seq=1 phase=before intno=0x30 eip=0x8001b030 cpu_interrupt_request=0x00000000 stack_hash=0x1111
BOOT_MARK b6 main-loop=timers context=browser-runtime seq=1 timer_progress=yes eip=0x8001b030 cpu_interrupt_request=0x00000002
EOF

out="$(python3 scripts/xbox-pfifo-transition-irq-timing.py \
    --native-log "${native_log}" \
    --browser-log "${browser_log}")"

case "${out}" in
    *"result=pass"*"divergence=none"*) ;;
    *)
        printf 'Expected no divergence, got:\n%s\n' "${out}" >&2
        exit 1
        ;;
esac

printf 'PFIFO_TRANSITION_IRQ_TIMING_SELFTEST result=pass\n'
