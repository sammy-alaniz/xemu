# 290 - Pre-Stream Vector Service Invariant Static

## Purpose

Define `pre_stream_vector_service_gate_replacement_invariant` from existing
source/history evidence, without runtime work or new instrumentation.

## Commands

```sh
rg -n "pre-stream vector|pre_stream|browser-lacks-pre-stream-vector-service|timer IRQ delivery|gated until PFIFO|pump|PIT bridge|precommit|normal-vblank|scheduler|post-STI|before-interrupt" \
  goal.md \
  history/28-timer-opportunity-v2-entry-ready-blocked.md \
  history/46-pfifo-scheduler-runtime-boundary.md \
  history/122-post-pfifo-pre-first-read-tcg-runtime.md \
  history/180-before-interrupt-quarantine-runtime-restored-boundary.md \
  history/206-dma-put-runtime-preservation-regressed.md \
  history/226-pre-tb-scheduler-runtime-shape-regressed.md \
  history/246-pit-bridge-plumbed-runtime.md \
  history/248-pit-bridge-quarantine-build.md \
  history/288-post-boundary-continuation-absence-static.md \
  history/289-post-boundary-absence-loop-check.md

rg -n "main_loop_timer_pump_ready|pfifo-ready-edge-qemu-pump|browser-headless-host-pump|timer-pump|XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE|XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP|xemu_xbe_boot_trace_main_loop_timer|pre_stream|PFIFO" \
  xemu-xbe.c xemu-xbe.h ui/xemu-headless.c util/main-loop.c \
  accel/tcg/cpu-exec.c accel/tcg/tcg-accel-ops.c

sed -n '990,1185p' xemu-xbe.c
sed -n '2360,2625p' xemu-xbe.c
sed -n '6860,6905p' xemu-xbe.c
sed -n '450,675p' ui/xemu-headless.c
```

## Inputs / Artifacts

- `xemu-xbe.c`
- `ui/xemu-headless.c`
- Recent negative history for pretransition/pump/PIT/scheduler branches.
- Stable ready-edge host4 evidence.

## Loop-Guard Field

- `pre_stream_vector_service_gate_replacement_invariant`

## Findings

- The active ready-edge path is PFIFO-empty gated:
  `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` returns true for
  ready-edge modes only when the latest NV2A wait snapshot is PFIFO empty.
- That explains the known absence: browser does not get native-like
  pre-stream vector service because timer delivery is intentionally gated until
  the stream-idle / pusher-empty state.
- Prior attempts to move service earlier are negative controls:
  - broad/early host pumping disturbed command-stream shape;
  - normal vblank made the CPU/IRQ boundary noisier;
  - PFIFO precommit and PIT bridge modes activated or partially activated but
    did not preserve the useful post-service edge;
  - pre-TB / before-interrupt scheduler paths regressed and were quarantined.
- Therefore the next design cannot be "pump earlier", "pump more", "turn vblank
  on", "revive PIT bridge", or "revive before-interrupt/pre-TB scheduler".

## Decision

Set the invariant to:

```text
pre_stream_vector_service_gate_replacement_invariant=deterministic-expired-timer-service-at-known-serviceable-idle-before-pfifo-empty-with-post-edge-preservation
```

Meaning any future code design must satisfy all of these before a runtime is
justified:

- It is driven by emulated state and virtual timer expiry, not browser wall
  clock or host polling count.
- It is main-loop/event-scheduler owned, not a TCG before-interrupt or pre-TB
  hook.
- It can name an exact serviceable guest state from existing evidence, such as
  the native pre-stream service/idle frame, instead of any generic
  pre-PFIFO-empty point.
- It does not deliver broad timers or device IRQs while PFIFO/PGRAPH command
  consumption is still active.
- It preserves the stable browser contract: B4/B5, read/load/entry-ready,
  section-map, PFIFO stream-idle, vector `0x30` service/IRET, and the
  `0x80030e84->0x80030f31` post-service edge.
- It must move `pre_service_browser_first_watch_read_ticks` upward from 0
  toward native 136 before being promoted.

## Next Step

Run the required bounded loop check. If approved, the next static step is to
map the native pre-stream serviceable state to existing browser observations and
decide whether a deterministic gate can be specified without new
instrumentation.
