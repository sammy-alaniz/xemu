# Edge Decision Runtime Loop Check

## Purpose

- One new fact this run was supposed to produce: whether a focused browser
  runtime with the new `edge-decision` marker is justified after the trace
  build passed.

## Command(s)

```sh
# Spawned bounded sub-agent critique after history/74.
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response only.
- Fixture assumptions: no emulation run.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- Important marker/comparator lines:
  - The proposed run is the first runtime use of `edge-decision`.
  - The narrowest next fact is which pre-TB input determines
    `0x80030e84->0x80030f31` versus `0x80030e84->0x80030f45`.
  - If limit 4 does not capture the comparable hit, record it as
    underdetermined instead of tuning warmup or rerunning broad probes.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a critique checkpoint only.

## Decision

- Status: current
- Why: the focused runtime is justified by the loop guard and targets
  `browser_post_service_top_edge`, with `browser_first_watch_read_ticks >= 1`
  as a guard.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: run once with the new marker and immediately reduce
  the edge-decision fields; do not treat generic B4/B5 or missing strict B6 as
  the result.

## Next Step

- Narrow follow-up: run one focused browser runtime with
  `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, then reduce the resulting
  `edge-decision` markers.
