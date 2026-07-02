# 311 - stable ready-edge strategy note

## Purpose

Produce the design-only strategy note requested by the post-310 loop check. The
exact field to explain before any new experiment is
`native_pre_stream_serviceable_state_browser_mapping`.

## Exact command

No shell command was required. This is a design-only note written with
`apply_patch`.

## Inputs and artifacts

- Current goal state:
  - `goal.md`
- Stable browser CPU-flow baseline:
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native reference baseline:
  - `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Negative diagnostic evidence:
  - deterministic PCRTC v1/v2 entries in histories 304-310

## Loop-guard fields

- `native_pre_stream_serviceable_state_browser_mapping`
- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Current interpretation

The stable ready-edge host4 browser baseline remains the primary CPU-flow
artifact because it preserves the useful shape: B4/B5/read/load/entry-ready,
section-map, PFIFO stream-idle, vector `0x30` service/IRET, and the comparable
post-service watch edge. It still fails strict B6 at
`missing-xbe-executed-marker` and remains far behind native at the first watched
`0x0003a890` read.

Native has a pre-stream serviceable state before the shared read: it reaches a
`pcrtc/intr-clear`-associated serviceable window and accumulates 136 tick units
before the comparable first watched read. Browser does not currently have an
equivalent pre-stream vector-service mapping. Deterministic PCRTC v2 proved that
we can force timer work at `pcrtc/intr-clear`, but that alone is insufficient:
it lost vector `0x30`, real IRET, the first-watch-read comparator window, and
the post-service watch edge.

## Strategy

1. Stop PCRTC runtime tuning as a promotion path. It explains one negative
   branch but does not preserve the stable B6 boundary.
2. Keep the ready-edge host4 combined log as the baseline for any next design.
3. The next design must name exactly how it changes or explains
   `native_pre_stream_serviceable_state_browser_mapping`.
4. Any future runtime must preserve all of these before judging tick movement:
   B4/B5, dashboard read/load/entry-ready, section-map, PFIFO stream-idle,
   vector `0x30` service, real IRET, and the `0x80030e84->0x80030f31`
   post-service watch edge.
5. A valid next design should target serviceability and ordering, not raw timer
   count. The useful question is not "can timers run at PCRTC?", but "why does
   browser fail to publish an interrupt-serviceable pre-stream state equivalent
   to native while keeping the stable ready-edge flow?"

## Decision

Do not run or patch next. The next work item should be a design-only causal
proposal from the stable ready-edge host4 baseline, with
`native_pre_stream_serviceable_state_browser_mapping` as the single field it can
change or explain.

## Next step

Run the required bounded sub-agent loop check for this strategy note. If it
approves, report the current status and next recommendation to the user instead
of starting another runtime.
