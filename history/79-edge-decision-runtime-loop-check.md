# Edge Decision Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the failed edge-decision runtime should be repeated, revised, or stopped before the next run.

## Command(s)

```text
Spawned read-only sub-agent 019f1df6-4272-7ca0-a593-28222132ee1e with this checkpoint:

Read goal.md and recent history entries 74-78. Decide whether the next action
should continue, revise, or stop after the deterministic edge-decision runtime
timed out before B4/dashboard read/section-map/stream-idle/edge-decision markers.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `history/78-edge-decision-runtime-early-timeout.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether the next run is justified for `browser_post_service_top_edge` / edge-decision marker presence, or would only repeat a known failed mode.

## Findings

- Result: critique decision was `revise`.
- The checkpoint said the last run changed the boundary to an early deterministic block before `entry_ready`; repeating the same deterministic run would be looping.
- It killed the hypothesis that history 78 explained `browser_post_service_top_edge`; that run never reached the boundary.
- It killed fixture-plumbing failure because the log showed `BROWSER_DIAGNOSTIC_APPLY name=xbe_edge_decision_limit value=4`.
- It kept edge-decision tracing as worth testing because the build passed and the failed runtime did not falsify the marker.
- It revised deterministic scheduling as currently configured because history 78 repeatedly showed `reason=deterministic-blocked ... entry_ready=no`.

## Decision

- Status: current
- Why: the next justified run must isolate edge-decision tracing from deterministic scheduling instead of repeating the early-timeout setup.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: run `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` on the known ready-edge host4 baseline with deterministic mode removed; use `POST_SERVICE_EDGE_DECISION_COMPARE classifications=edge_trace:<missing-stream-idle-boundary|useful-post-service-edge>` and `browser_post_service_top_edge` as the fields.

## Next Step

- Narrow follow-up: run the ready-edge host4 browser baseline with `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, omitting `XEMU_BROWSER_BOOT_DETERMINISTIC` and `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS`, then reduce it with the existing evidence checkers and post-service edge comparator.
