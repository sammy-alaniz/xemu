# Post-Service Edge Decision Loop Check

## Purpose

- One new fact this run was supposed to produce: whether the next action after
  history/70 should patch deterministic scheduling or first explain the
  `0x80030e84` edge decision.

## Command(s)

```sh
# Spawned bounded sub-agent critique after history/70.
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Additional browser logs:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`,
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log`
- Output directory/log: sub-agent response only.
- Fixture assumptions: no emulation run.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `revise`.
- Important marker/comparator lines:
  - History/70 showed deterministic v1 improves ticks but changes the
    `0x80030e84` block exit to `0x80030f45`.
  - Warmup1 loses the focused read path and falls back to
    `0x8001b02f->0x8001b030`.
  - The next fact should identify why the first `0x80030e84` block exits to
    `0x80030f45` instead of the useful baseline `0x80030f31`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a critique checkpoint only.

## Decision

- Status: current
- Why: raw warmup-count tuning is now killed as the main knob, and patching
  scheduling before explaining the branch condition is too weak.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: inspect the `0x80030e84` edge decision first; add a
  narrow trace only if inspection does not identify the condition.

## Next Step

- Narrow follow-up: inspect the code/marker context around the first
  `0x80030e84` block exit and identify the state difference that changes
  `browser_post_service_top_edge`.
