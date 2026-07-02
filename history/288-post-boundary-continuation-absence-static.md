# 288 - Post-Boundary Continuation Absence Static

## Purpose

Classify `post_boundary_guest_progress_to_dma_continuation_absence_cause` from
existing stable CPU/wait/timer evidence only.

## Commands

```sh
scripts/xbox-post-command-loop-clusters.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-command-handoff-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-idle-interrupt-flow-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs / Artifacts

- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Loop-Guard Field

- `post_boundary_guest_progress_to_dma_continuation_absence_cause`

## Findings

- `POST_COMMAND_LOOP_CLUSTERS` reports
  `after_idle_divergence=memory-poll-mismatch`.
- Browser after-idle state is dominated by
  `nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty`, with 32 after-idle
  samples and latest edge `0x8001b02f->0x8001b030`.
- Browser after-idle latest state has interrupts enabled, no pending interrupt,
  no CPU interrupt request, and `dma_get=dma_put=0x03881318`.
- Native after-idle eventually reaches latest wait
  `pgraph-notify-clear/notify-error-clear`, with latest DMA state beyond the
  browser boundary and strict `dashboard=xbe-executed`.
- `POST_COMMAND_HANDOFF_COMPARE` reports `divergence=native-xbe-executed-only`;
  browser remains stream-idle while native no longer has a shared stream-idle
  terminal shape.
- `POST_IDLE_INTERRUPT_FLOW_COMPARE` reports
  `divergence=missing-interrupt-service`: browser services vector `0x30`
  after stream-idle, while the native post-idle flow proceeds through a larger
  device/interrupt sequence and later handoff.
- `PRE_STREAM_TICK_SOURCE_COMPARE` reports
  `divergence=browser-lacks-pre-stream-vector-service`: native has pre-stream
  timer progress, hard IRQ, PIC ack `0x30`, service `0x30`, and IRET; browser
  has none before stream-idle and only services vector `0x30` after stream-idle.

## Decision

Classify the absence cause as:

```text
post_boundary_guest_progress_to_dma_continuation_absence_cause=browser-stuck-empty-pfifo-wait-after-late-vector-service
```

The stable browser is not failing PFIFO consumption or PGRAPH decode. It reaches
empty PFIFO at `0x03881318`, then services vector `0x30` late and settles back
into an empty-PFIFO wait/poll path with no pending interrupt and no later
producer continuation. Native accumulates pre-stream timer/vector service and
continues into a later PGRAPH notify-clear regime before strict dashboard
execution.

## Next Step

Run the required bounded loop check. The next causal question should target why
browser lacks native-like pre-stream vector service/tick progression before the
shared stream-idle boundary, using existing evidence before adding any new
instrumentation.
