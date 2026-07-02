# First Watch Read Ticks Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to stop edge-decision schema work and pivot to a behavioral/deterministic ordering change focused on `browser_first_watch_read_ticks`.

## Command(s)

```text
Spawned read-only sub-agent 019f1e0f-a321-70b3-8e6a-cb1a01a747c9 with this checkpoint:

Read goal.md, history/91, and history/92. Decide whether to continue, revise,
or stop after the final edge-decision runtime proved the target edge
0x80030e84->0x80030f31 is reached with current PFIFO stream-idle, while browser
still reads 0 ticks before that block.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log`
- Latest combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1-combined.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether the next work should target `browser_first_watch_read_ticks` or continue edge-decision diagnostics.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said edge-decision is answered: target PC and edge are reached, PFIFO stream-idle is visible, and the block advances `0x0003a890` by one tick.
- It killed these hypotheses: target PC/edge not reached, PFIFO stream-idle unavailable at the edge, and the `0x80030e84->0x80030f31` block itself is broken.
- It kept the hypothesis that browser reaches the dashboard execution path too early in emulated timer/order state.
- It revised the blocker to: CPU reaches the first watched read before timer tick accumulation.
- The narrowest next fact is whether a deterministic browser ordering change can move `browser_first_watch_read_ticks` from `0` to `>0` before `0x80014f32->0x80030e84`, while preserving the existing gates.

## Decision

- Status: current
- Why: the next primary field should be `browser_first_watch_read_ticks`, not more edge-decision instrumentation.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: make one narrow opt-in deterministic ordering change that drains/dispatches boot-critical timer work before the first `0x80014f32->0x80030e84` watched-read path.

## Progress-Method Critique

- No more edge-decision schema work.
- For the next 2-3 turns, every action should be tied to `browser_first_watch_read_ticks` or `browser_dashboard_xbe_executed`.
- Avoid broad B3/B4/B5, display, native, PFIFO-window, pusher, scheduler, or edge-decision diagnostics unless a deterministic ordering change regresses a preserved gate and that regressed field is named first.

## Next Step

- Narrow follow-up: inspect the existing deterministic/timer-pump ordering hooks to identify one code path that can move `browser_first_watch_read_ticks` from `0` to `>0` before the first watched read.
