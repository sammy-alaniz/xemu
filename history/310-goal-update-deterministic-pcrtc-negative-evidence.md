# 310 - goal update deterministic PCRTC negative evidence

## Purpose

Update `goal.md` after history/309 and the required loop check. The field
recorded is `browser_pre_stream_vector_service_state`, with a decision not to
promote the deterministic PCRTC branch over the stable ready-edge host4
baseline.

## Exact command

No shell command was required. Edited `goal.md` with `apply_patch`.

## Inputs and artifacts

- Updated:
  - `goal.md`
- Evidence referenced:
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log`
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2-combined.log`
  - `history/304-deterministic-pcrtc-prestream-runtime-raw-result.md`
  - `history/305-deterministic-pcrtc-prestream-log-classification.md`
  - `history/306-deterministic-pcrtc-prestream-static-design-inspection.md`
  - `history/307-deterministic-pcrtc-boundary-preservation-patch.md`
  - `history/308-deterministic-pcrtc-prestream-v2-runtime-raw-result.md`
  - `history/309-deterministic-pcrtc-v2-helper-reduction.md`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Findings

1. `goal.md` now records deterministic PCRTC v1 as
   `browser_pre_stream_vector_service_state=pre-entry-dead-zone`.
2. `goal.md` now records deterministic PCRTC v2 as
   `browser_pre_stream_vector_service_state=pcrtc-intr-clear-pumped-but-no-vector-service`.
3. The update notes that v2 restored B5 runtime, B4 display capture, dashboard
   read/load, entry-ready, and section-map evidence.
4. The update also notes that v2 still fails strict B6 at
   `missing-xbe-executed-marker`, loses vector `0x30` service/real IRET, and
   fails the comparable first-watch-read/post-service-edge path with
   `missing-first-watch-read` and
   `missing-browser-pre-edge,browser-post-edge`.
5. The decision in `goal.md` is explicit: do not tune or promote the
   deterministic PCRTC branch over the stable ready-edge host4 baseline.

## Decision

The deterministic PCRTC branch is closed as a promotion path unless a future
design names a new field and preserves vector service, IRET, and post-service
watch-edge evidence. The stable ready-edge host4 combined log remains the
primary B6 CPU-flow baseline.

## Next step

Run the required bounded sub-agent loop check. The next work should be a
strategy revision from the stable baseline, not another PCRTC runtime, unless a
new design explains how it preserves the lost vector-service/IRET edge.
