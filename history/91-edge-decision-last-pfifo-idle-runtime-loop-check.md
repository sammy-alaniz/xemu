# Edge Decision Last PFIFO Idle Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the compiled last-PFIFO-idle diagnostic justifies one targeted browser runtime.

## Command(s)

```text
Spawned read-only sub-agent 019f1e0b-350b-7360-ac55-b205c65b15fc with this checkpoint:

Read goal.md, history/89, and history/90. Decide whether to run exactly one
ready-edge host4 browser runtime with XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4,
deterministic mode off, to populate last_pfifo_idle_* fields at target PC.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest build artifact: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether one runtime is justified to populate `edge_decision_current_vs_last_pfifo_idle_context` and `edge_decision_last_pfifo_idle_present_at_target_pc`.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said this is not yet looping because the last step was build-only validation and the new runtime evidence has not been collected.
- The narrowest next fact is whether `edge_decision_last_pfifo_idle_present_at_target_pc=yes` while the current/latest wait snapshot still reports a non-PFIFO context.
- It killed the target-PC-never-reached hypothesis as already disproven.
- It kept the hypothesis that the current/latest wait snapshot can be overwritten by PCRTC/vblank suppression.
- It said one ready-edge host4 runtime is justified because no static probe or build can answer whether the retained PFIFO-idle snapshot is present at target PC in browser execution.

## Decision

- Status: current
- Why: one runtime can populate the newly compiled `last_pfifo_idle_*` fields and directly answer the current boundary question.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: run once, then move to a behavioral/deterministic ordering change if last PFIFO idle is present, or abandon this marker path if it is absent.

## Progress-Method Critique

- This must remain the last marker/schema iteration for the edge-decision boundary.
- After the runtime, do not add more edge-decision fields.
- If `last_pfifo_idle_*` shows PFIFO idle was present at target PC, move to a behavioral change or deterministic ordering fix that uses a stable PFIFO context.
- If absent, stop pursuing this edge-decision marker path and return to deterministic PFIFO/PCRTC/timer ordering.
- If strict `dashboard=xbe-executed` appears unexpectedly, advance to main-menu capture evidence.

## Next Step

- Narrow follow-up: run exactly one ready-edge host4 browser runtime with `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, deterministic mode off, and reduce `last_pfifo_idle_*`.
