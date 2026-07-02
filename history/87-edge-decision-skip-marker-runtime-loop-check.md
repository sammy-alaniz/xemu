# Edge Decision Skip Marker Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the newly built `edge-decision-skip` diagnostic justifies one targeted browser runtime run.

## Command(s)

```text
Spawned read-only sub-agent 019f1e03-0522-7141-91b1-11e03c7810a7 with this checkpoint:

Read goal.md plus history/83 and history/86. Decide whether to run exactly one
ready-edge host4 browser runtime with XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4,
deterministic mode off, to collect either edge-decision-skip or edge-decision
markers.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest build artifact: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether one runtime is justified to populate `edge_trace_marker_absence_reason`.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said this is not yet looping because the marker was revised and built, but no runtime has populated the new field yet.
- The narrowest next fact is `edge_trace_marker_absence_reason`: whether target-PC hits are absent, skipped by cheap gates, skipped by stream/PFIFO state, or reaching the heavier `edge-decision` path.
- It killed build/fixture plumbing as the marker-absence explanation because the WASM build linked the patched artifact.
- It kept edge-decision tracing as targeting a real dashboard-execution boundary.
- It revised the interpretation of marker absence: with `edge-decision-skip`, absence can mean no target-PC hit, limit not hit, or an earlier gate still prevents emission.

## Decision

- Status: current
- Why: one ready-edge host4 browser runtime with deterministic mode off can change the new field without branching back into broad diagnostics.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: run once, reduce only the new edge-decision marker fields first, and keep B4/B5 checks as regression guards rather than the objective.

## Progress-Method Critique

- The critique said this runtime is worth the cost because B4/B5 are regression guards here; the objective is the new marker outcome.
- The next 2-3 turns should stay focused: run once, reduce `edge-decision-skip` / `edge-decision`, then either fix the identified cheap-gate/ordering cause or stop if the marker remains absent and define a narrower instrumentation point.
- It explicitly warned not to branch back into generic timer, PFIFO, vblank, or B4/B5 diagnostics.

## Next Step

- Narrow follow-up: run exactly one ready-edge host4 browser runtime with `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, deterministic mode off, then reduce `edge_trace_marker_absence_reason`.
