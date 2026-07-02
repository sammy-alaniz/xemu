# Edge Decision Last PFIFO Idle Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to revise the edge-decision diagnostic after `edge-decision-skip` proved target PC `0x80030e84` is reached but gated out by the latest wait snapshot.

## Command(s)

```text
Spawned read-only sub-agent 019f1e07-2410-7361-b90e-aaae4fc7ea67 with this checkpoint:

Read goal.md and history/88. Decide whether to rerun, revise, or stop after
`edge-decision-skip` reported `reason=stream-idle-gate-false` with current wait
`pcrtc/vblank-suppress`, while earlier markers showed PFIFO stream-idle before
the target-PC hit.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log`
- Latest combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1-combined.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: `edge_decision_current_vs_last_pfifo_idle_context` and `edge_decision_last_pfifo_idle_present_at_target_pc`.

## Findings

- Result: critique decision was `revise`.
- The checkpoint killed the hypothesis that the marker was absent because target PC `0x80030e84` was never reached.
- It kept the hypothesis that a useful PFIFO stream-idle boundary exists before the target-PC hit.
- It revised the interpretation of `stream-idle-gate-false`: it means the latest global wait snapshot is not PFIFO idle, not necessarily that PFIFO was not recently idle.
- It noted PCRTC suppression can overwrite the latest wait snapshot via the global NV2A wait-state observer.
- It recommended adding a diagnostic-only source-specific last PFIFO idle snapshot, updated from PFIFO stream-idle boundary/transition observation, and emitting both current wait and last PFIFO-idle wait in `edge-decision-skip`.

## Decision

- Status: current
- Why: the next change should explain whether current `pcrtc/vblank-suppress` is overwriting an earlier PFIFO-idle context at the target PC.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: add `edge_decision_last_pfifo_idle_present_at_target_pc` evidence; do not let it satisfy strict `dashboard=xbe-executed`.

## Progress-Method Critique

- The critique said this is still aligned with the main-menu/game-launch goal because strict browser dashboard execution remains the M1 prerequisite.
- It warned the work is close to over-investing in instrumentation.
- Process constraint for the next 2-3 turns: one more marker/schema iteration maximum for this edge-decision boundary. It must produce actionable edge context at `0x80030e84` or force a move back to deterministic PFIFO/PCRTC/timer ordering.
- No repeated runtime without a code/log-field change tied to `browser_dashboard_xbe_executed`.

## Next Step

- Narrow follow-up: add diagnostic-only tracking for the last PFIFO stream-idle wait snapshot and emit it from `edge-decision-skip` beside the current wait snapshot.
