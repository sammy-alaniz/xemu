# Post-Service Edge Decision Static Compare

## Purpose

- One new fact this run was supposed to produce: whether the current browser
  artifacts explain the `browser_post_service_top_edge` change without starting
  another emulation run.

## Command(s)

```sh
python3 -m py_compile scripts/xbox-post-service-edge-decision-compare.py
rg -n "\\bfield\\(" scripts/xbox-post-service-edge-decision-compare.py
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log det2=build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log --log warmup1=build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: none; this was browser-artifact-only static reduction.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Additional browser logs:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`,
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log`
- Output directory/log: terminal output from
  `scripts/xbox-post-service-edge-decision-compare.py`.
- Fixture assumptions: existing logs only; no emulation was started.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: `POST_SERVICE_EDGE_DECISION_COMPARE result=pass`.
- Important marker/comparator lines:
  - `classifications=baseline:useful-post-service-edge,det2:block-start-branch-mismatch,warmup1:watch-write-without-focused-read`
  - `top_edges=baseline:0x80030e84->0x80030f31,det2:0x80030e4c->0x80014f32,warmup1:0x8001b02f->0x8001b030`
  - Baseline reaches the useful focused block:
    `first_block_edge=0x80030e84->0x80030f31`,
    `first_watch_read_ticks=1`, `first_watch_write_ticks=1`.
  - Deterministic v1 still reaches the watched read, but the block exits to
    `0x80030f45` instead of `0x80030f31`:
    `first_watch_read_edge=0x80014f32->0x80030e84`,
    `first_watch_read_ticks=2`,
    `first_block_edge=0x80030e84->0x80030f45`,
    `first_block_tb_exit=1`.
  - Warmup1 loses the focused read path:
    `classification=watch-write-without-focused-read`,
    `first_watch_read_line=0`,
    `first_watch_write_eip=0x80030e84`,
    `top_edge=0x8001b02f->0x8001b030`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not remeasured; this was a static comparison of existing browser-runtime
  artifacts. The prior runtime histories already recorded the B4/B5 and strict
  B6 outcomes for those artifacts.

## Decision

- Status: current
- Why: this explains the post-service edge regression and kills raw warmup-count
  tuning as the main knob. Deterministic delivery can move the watched ticks,
  but it must preserve the focused CPU-flow edge.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history/69 approved fixing and rerunning this
  reducer before any new experiment; no newer critique has been run yet.

## Next Step

- Narrow follow-up: run the required loop-check, then add a focused
  edge-decision trace or deterministic scheduling change that preserves
  `0x80030e84->0x80030f31` while keeping the tick improvement.
