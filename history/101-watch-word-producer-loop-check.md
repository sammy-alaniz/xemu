# Watch Word Producer Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the static
  producer-path finding justifies code work, another runtime, or stopping.

## Command(s)

```text
Spawned read-only sub-agent 019f1e20-d876-7211-8c4f-cdd8c2670d45 with this checkpoint:

Read goal.md, AGENTS.md, history/98, history/99, and history/100. Evaluate the
static-inspection finding that physical 0x0003a890 is produced by guest CPU
execution in/around the 0x80030e84 tick-update block, while host timer pumps
only assert/deassert PIT/PIC state. Compare candidate next directions:

A. Add a compact diagnostic/comparator that counts completed
   0x80030e84->0x80030f31 tick-block executions before stream-idle / first
   watched read.
B. Make a deterministic scheduler change that pairs PIT delivery with guest CPU
   execution before the first dashboard/post-idle read.

Answer the standard loop-check questions, include a Progress-Method Critique,
and end with one decision: continue, revise, or stop.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log`
- Latest static summary: `history/100-watch-word-producer-static-inspection.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `browser_first_watch_read_ticks`, `browser_dashboard_xbe_executed`

## Findings

- Result: critique decision was `revise`.
- The checkpoint said we are only looping if the next step is another
  ready-edge/timer-step/runtime variant.
- It kept the current direction only if it moves to the guest tick-block
  completion/order boundary.
- It named the narrowest next field as
  `pre_first_read_tick_block_completions_browser`: whether browser completes
  any `0x80030e84->0x80030f31` tick-update blocks before the first watched read,
  compared with native.
- It killed the hypothesis that more host timer callbacks alone will move
  `browser_first_watch_read_ticks`.
- It killed the hypothesis that the `0x80030e84->0x80030f31` block arithmetic
  is wrong.
- It kept the hypothesis that browser reaches the dashboard/post-idle path too
  early relative to native emulated timer and guest CPU order.
- It revised the core problem to: PIT/PIC delivery is not followed by enough
  ordered guest CPU execution of the tick-update path before the dashboard or
  post-idle read.

## Decision

- Status: current
- Why: the next action should be one bounded code+runtime bundle, not another
  standalone diagnostic series.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: combine the two candidate directions into one
  narrow implementation step: add a compact tick-block completion
  marker/counter, then use that as the guardrail for a gated deterministic
  PIT-to-guest-exec scheduler path.

## Progress-Method Critique

- The critique said `browser_first_watch_read_ticks` is still connected to the
  real goal because it is the sharpest causal proxy for missing strict browser
  `dashboard=xbe-executed`; main-menu proof and game launch remain downstream.
- It warned that a standalone comparator series would become over-diagnostic.
  One compact counter is useful; another runtime that only reconfirms zero ticks
  is not.
- It said the history and loop-check process is helping by blocking repeated
  pump/vblank/B3/B4/B5 paths, but would slow the next 2-3 turns if every small
  static read triggers another checkpoint.
- It recommended code change as the right next mode.
- Process adjustment for the next 2-3 turns: allow exactly one implementation
  bundle and one runtime validation before another critique, unless the work
  broadens scope or weakens the B6/main-menu/game-launch evidence contract.

## Next Step

- Narrow follow-up: implement an opt-in, compact tick-block completion
  marker/counter for the `0x80030e84->0x80030f31` path and use it to gate the
  next deterministic PIT-to-guest-execution experiment.
