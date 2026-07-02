# 188. Stable Baseline Boundary Field Selection

## Purpose

Select the next narrow boundary-moving field from the stable ready-edge host4
combined baseline before any code change or runtime run, explicitly excluding
the quarantined before-interrupt micro-scheduler path.

## Commands

```sh
scripts/xbox-b6-current-boundary.sh

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "0x80014f32|0x80030e84|browser-ready-edge-qemu-pump|browser-headless-host-pump-bounded|timer-pump|main-loop=timers|memory-watch|tick-block|hard-irq-service|iret|before_interrupt|after_tb|pre_first_read" \
  xemu-xbe.c accel/tcg/cpu-exec.c ui/xemu-headless.c scripts | head -240
```

## Inputs / Artifacts

- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser CPU-flow baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Current source files:
  - `xemu-xbe.c`
  - `accel/tcg/cpu-exec.c`
  - `ui/xemu-headless.c`

## Loop-Guard Field

- `stable_baseline_next_boundary_field_selected`

## Findings

The stable ready-edge host4 combined baseline remains the right front-most
diagnostic:

- strict B6 still fails at `missing-xbe-executed-marker`
- section-map evidence passes
- native actual dashboard execution still passes
- post-service watch edge still passes with matched block delta
- pre-service tick gap still passes with
  `divergence=browser-first-watch-read-before-catchup`

The sharp measured gap is unchanged:

- native first watched read: 136 ticks at `0x80014f5f->0x80030e84`
- browser first watched read: 0 ticks at `0x80014f32->0x80030e84`
- browser first timer source: `browser-ready-edge-qemu-pump`
- browser first service before read: vector `0x30` at `0x8001b030`
- browser first IRET after service: `0x80030f31`
- post-service block delta matches one tick, so the problem is accumulated
  state before the first watched read, not the arithmetic inside
  `0x80030e84->0x80030f31`

The current boundary helper also keeps the earlier timer/PFIFO finding alive:

- `B6_CURRENT_BOUNDARY_PRE_STREAM_TICK_SOURCE` reports
  `divergence=browser-lacks-pre-stream-vector-service`
- `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT` reports
  `divergence=no-pfifo-window-published-before-opportunities`
- `B6_CURRENT_BOUNDARY_PFIFO_WINDOW_PUBLICATION` reports PFIFO production starts
  after the timer-opportunity window
- `B6_CURRENT_BOUNDARY_PFIFO_PUSHER_ENTRY` reports pusher entry after the
  opportunity window
- `B6_CURRENT_BOUNDARY_PFIFO_SCHEDULER_STATE` is skipped because scheduler
  markers are missing, with `first_kick_after_last_opportunity_source=none`

## Decision

Selected next field:

- `first_kick_after_last_opportunity_source`

This is the next useful boundary field because existing artifacts already show
expired timer opportunities before PFIFO window publication, but they do not
identify the source of the first scheduler/kick event after that opportunity
window. Filling that field is static/code-instrumentation work around PFIFO
scheduler source tagging, not another post-STI before-interrupt scheduler run.

## Next Step

Run the required bounded loop check. If it agrees, inspect the PFIFO scheduler
call sites and marker code to design a non-perturbing source-tagged marker that
can populate `first_kick_after_last_opportunity_source` while preserving the
stable ready-edge host4 boundary.
