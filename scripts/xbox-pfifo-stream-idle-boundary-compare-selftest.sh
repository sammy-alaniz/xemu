#!/usr/bin/env bash
set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

native_log="$tmpdir/native.log"
browser_log="$tmpdir/browser.log"
missing_log="$tmpdir/missing.log"
missing_out="$tmpdir/missing.out"

cat >"$native_log" <<'LOG'
BOOT_MARK b6 pfifo=window context=native-headless seq=377 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=native-headless stream_idle=yes start_pc=0x8001b030 next_pc=0x8001b02f loop_kind=backward interrupts_enabled=yes irq_inhibited=yes cpu_interrupt_request=0x00000000 pending_interrupt=no
LOG

cat >"$browser_log" <<'LOG'
BOOT_MARK b6 pfifo=window context=browser-runtime seq=379 op=pusher-empty dma_get=0x03881318 dma_put=0x03881318
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime stream_idle=yes start_pc=0x8001b02f next_pc=0x8001b030 loop_kind=fallthrough interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 pending_interrupt=no
LOG

out=$(scripts/xbox-pfifo-stream-idle-boundary-compare.py \
    --native-log "$native_log" \
    --browser-log "$browser_log")
grep -q 'result=pass' <<<"$out"
grep -q 'divergence=first-stream-idle-loop-mismatch' <<<"$out"
grep -q 'native_boundary=missing' <<<"$out"
grep -q 'browser_boundary=missing' <<<"$out"

cat >>"$native_log" <<'LOG'
BOOT_MARK b6 pfifo=stream-idle-boundary context=native-headless seq=1 wait_seq=377 wait_source=pfifo-window wait_op=pusher-empty dma_get=0x03881318 dma_put=0x03881318 eip=0x8001b030 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 last_transition_start_pc=0x8001b030 last_transition_next_pc=0x8001b02f last_transition_next_pc_known=yes
LOG

cat >>"$browser_log" <<'LOG'
BOOT_MARK b6 pfifo=stream-idle-boundary context=browser-runtime seq=1 wait_seq=379 wait_source=pfifo-window wait_op=pusher-empty dma_get=0x03881318 dma_put=0x03881318 eip=0x8001b02f interrupts_enabled=yes irq_inhibited=yes cpu_interrupt_request=0x00000000 last_transition_start_pc=0x8001b02f last_transition_next_pc=0x8001b030 last_transition_next_pc_known=yes
LOG

out=$(scripts/xbox-pfifo-stream-idle-boundary-compare.py \
    --native-log "$native_log" \
    --browser-log "$browser_log")
grep -q 'result=pass' <<<"$out"
grep -q 'divergence=boundary-cpu-state-mismatch' <<<"$out"
grep -q 'native_boundary=present' <<<"$out"
grep -q 'browser_boundary=present' <<<"$out"

cat >>"$native_log" <<'LOG'
BOOT_MARK b6 pfifo=stream-idle-transition context=native-headless seq=1 wait_seq=1 wait_source=pfifo-transition wait_op=pusher-empty-transition dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 method=0x1d90 processed=1 eip=0x80042910 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 last_transition_start_pc=0x800426de last_transition_next_pc=0x80042910 last_transition_next_pc_known=yes
LOG

cat >>"$browser_log" <<'LOG'
BOOT_MARK b6 pfifo=stream-idle-transition context=browser-runtime seq=1 wait_seq=1 wait_source=pfifo-transition wait_op=pusher-empty-transition dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 method=0x1d90 processed=1 eip=0x8001b030 interrupts_enabled=yes irq_inhibited=no cpu_interrupt_request=0x00000000 last_transition_start_pc=0x8001b030 last_transition_next_pc=0x8001b02f last_transition_next_pc_known=yes
LOG

out=$(scripts/xbox-pfifo-stream-idle-boundary-compare.py \
    --native-log "$native_log" \
    --browser-log "$browser_log")
grep -q 'result=pass' <<<"$out"
grep -q 'divergence=transition-cpu-state-mismatch' <<<"$out"
grep -q 'native_transition=present' <<<"$out"
grep -q 'browser_transition=present' <<<"$out"

cat >"$missing_log" <<'LOG'
BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime stream_idle=no
LOG

if scripts/xbox-pfifo-stream-idle-boundary-compare.py \
    --native-log "$missing_log" \
    --browser-log "$browser_log" >"$missing_out"; then
    cat "$missing_out"
    echo "expected missing PFIFO idle window to fail" >&2
    exit 1
fi
grep -q 'result=fail' "$missing_out"
grep -q 'divergence=missing-pfifo-idle-window' "$missing_out"

echo "xbox-pfifo-stream-idle-boundary-compare selftest passed"
