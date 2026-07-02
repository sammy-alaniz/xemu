# Post-Service Edge Decision Loop Check

## Purpose

- One new fact this run was supposed to produce: whether fixing and rerunning
  the static reducer after history/68 would repeat a loop or remain justified
  by the active boundary.

## Command(s)

```sh
# Spawned bounded sub-agent critique after history/68.
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response only.
- Fixture assumptions: no emulation run; proposed action uses existing browser
  logs only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- Important marker/comparator lines:
  - The failed history/68 reducer did not produce boot evidence because the
    script crashed before output.
  - The narrowest next fact is whether deterministic variants lose the useful
    `0x80030e84->0x80030f31` edge and fall into `0x8001b02f->0x8001b030` or
    another edge.
  - Raw warmup-count tuning should be killed as the main control knob.
  - Deterministic timer delivery should be revised to preserve CPU-flow edge
    invariants, not just add earlier timer progress.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a critique checkpoint only.

## Decision

- Status: current
- Why: the next action fixes a local static-helper bug and reruns the exact
  reducer that history/68 failed to execute.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: no better experiment should replace the static
  reducer until it succeeds; if it explains the edge divergence but not cause,
  add a narrow edge-decision trace next.

## Next Step

- Narrow follow-up: rename the reducer's local marker-field helper, rerun it on
  the three existing browser logs, and keep `browser_post_service_top_edge` as
  the only target field.
