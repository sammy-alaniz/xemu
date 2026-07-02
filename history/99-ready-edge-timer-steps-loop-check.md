# Ready Edge Timer Steps Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue with more ready-edge timer-step runtimes, revise toward static producer-path inspection, or stop.

## Command(s)

```text
Spawned read-only sub-agent 019f1e19-c01e-7342-9c7a-7733af06bc54 with this checkpoint:

Read goal.md and history/93-98. Evaluate the steps=2 runtime, where
`browser_first_watch_read_ticks` stayed 0, extra timer callbacks appeared before
the first watched read, and the post-service edge shape regressed. Answer the
standard loop-check questions, include a `Progress-Method Critique`, and end
with one decision: continue, revise, or stop.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log`
- Latest combined log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1-combined.log`
- Latest run summary: `history/98-ready-edge-timer-steps-runtime.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether the next action is justified for `browser_first_watch_read_ticks`.

## Findings

- Result: critique decision was `revise`.
- The checkpoint said we are looping if the next move is another ready-edge step-count runtime or edge-decision schema pass.
- It killed the hypothesis that one more ready-edge timer step will naturally move the first watched read above zero.
- It also killed the idea that the useful post-service edge block itself is the primary problem.
- It kept the broader hypothesis that browser reaches the dashboard path too early relative to native emulated timer/order state.
- It revised the current cause from raw timer callback count to producer routing/order.
- The narrowest next fact is to identify which producer writes physical `0x0003a890`, and whether a ready-edge timer callback before the first watched read can reach that producer.

## Decision

- Status: current
- Why: another runtime is not justified until static inspection names a specific producer/order path tied to `browser_first_watch_read_ticks`.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: replace runtime probing with a bounded static-inspection bundle covering the watched-word producer, timer callback source, and CPU resume ordering.

## Progress-Method Critique

- The critique said the metrics remain tied to main-menu/game-launch success because `browser_dashboard_xbe_executed` is still the required prerequisite.
- It sharpened the sub-metric: `browser_first_watch_read_ticks` matters because it explains the missing strict dashboard execution marker, not as a standalone success signal.
- It said the history and loop-check process helps when it blocks repeated B3/B4/B5, edge-decision, and timer-step reruns, but slows work if every tiny static read becomes a checkpoint.
- It recommended one bounded static-inspection bundle before another loop-check: producer write path, timer callback source, and CPU resume ordering.

## Next Step

- Narrow follow-up: update `goal.md` so future loop checks always include `Progress-Method Critique`, then perform the bounded static-inspection bundle without starting another runtime.
