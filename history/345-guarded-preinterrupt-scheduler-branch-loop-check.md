# Guarded Preinterrupt Scheduler Branch Loop Check

## Purpose

- One new fact this run was supposed to produce: whether to continue, revise, or
  stop the guarded preinterrupt scheduler branch after runtime V2.

## Command(s)

```sh
# Bounded sub-agent loop check; no shell command.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response for the required loop check after
  `history/344-guarded-preinterrupt-scheduler-runtime-v2.md`
- Fixture assumptions: explicit fixture paths are now proven; the next blocker
  is runtime behavior, not missing assets.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_scheduler_timer_delivery_no_watch_update_reason`.

## Findings

- Result: loop check completed.
- Important marker/comparator lines: revise the guarded scheduler branch; do
  not continue it as-is. Runtime V2 proves the scheduler fires, but it leaves
  the first watched read at 0 ticks, only advances the tick block after that
  read, lacks strict `dashboard=xbe-executed`, and appears to lose IRET
  preservation.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? This
  was a review checkpoint, not a runtime. It accepts history 344's result that
  IRET preservation regressed in the runtime artifact.

## Decision

- Status: current
- Why: another guarded runtime retry would repeat a known negative result unless
  a static/code finding first explains why timer delivery does not update
  physical `0x0003a890` before the first watched read.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: use the narrower field
  `pre_first_read_scheduler_timer_delivery_no_watch_update_reason` and require
  a static causal explanation before any further runtime.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method is close to becoming
  circular because recent work keeps proving pump placement can fire without
  advancing the dashboard execution boundary.
- If yes, process adjustment for next 2-3 turns: identify the exact producer
  path expected to update `0x0003a890`, its required CPU/timer/IRQ preconditions,
  and why the guarded scheduler did not satisfy them before considering any
  runtime.

## Next Step

- Narrow follow-up: static causal trace for
  `pre_first_read_scheduler_timer_delivery_no_watch_update_reason`; no runtime
  retry until that field changes.
