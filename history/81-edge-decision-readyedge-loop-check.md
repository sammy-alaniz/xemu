# Edge Decision Ready-Edge Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the ready-edge edge-decision run should be rerun after fixing the missing output directory.

## Command(s)

```text
Spawned read-only sub-agent 019f1df8-8924-7ff0-bea6-249e89cc3c4e with this checkpoint:

Read goal.md plus history/79-edge-decision-runtime-loop-check.md and
history/80-edge-decision-readyedge-missing-output-dir.md. Decide whether
creating the missing output directory and rerunning the same ready-edge host4
edge-decision experiment is justified.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: intended `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether the next run is justified for `browser_post_service_top_edge` and edge-decision classification.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said history 80 produced no runtime evidence because it failed before launch due to a missing output directory.
- The narrowest next fact remains whether ready-edge host4 plus `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, without deterministic scheduling, reaches the known post-service boundary and emits useful `edge-decision` evidence.
- It killed deterministic scheduling as currently configured, kept edge-decision tracing on the known ready-edge host4 baseline, and revised only the setup to create the output directory before shell redirection.
- It said there is no better experiment before this one; the setup fix can change or explain `browser_post_service_top_edge` and edge-decision classification.

## Decision

- Status: current
- Why: rerunning after creating the missing directory is mechanically unblocked and is not repeating a negative runtime experiment.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: create `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/`, then rerun the same ready-edge host4 command without deterministic scheduling.

## Next Step

- Narrow follow-up: create the output directory and rerun the ready-edge host4 edge-decision experiment.
