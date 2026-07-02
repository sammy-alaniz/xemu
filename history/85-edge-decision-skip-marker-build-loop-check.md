# Edge Decision Skip Marker Build Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the sandbox-failed podman build should be retried with escalation, revised, or stopped.

## Command(s)

```text
Spawned read-only sub-agent 019f1e01-0084-7961-9149-656c2bc8c238 with this checkpoint:

Read goal.md plus history/83 and history/84. Decide whether to rerun the exact
same podman WASM build with sandbox escalation after sandboxed podman failed
before compilation on `/run/user/1000/libpod`.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: none; checkpoint only.
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether to rerun the build to test compile viability of the `edge_trace_marker_absence_reason` diagnostic.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said this was not a semantic loop because the last failure did not compile or remeasure runtime behavior.
- It killed the idea that the failed build says anything about the patch.
- It kept the hypothesis that marker absence is probably due to target-PC hits failing cheap gates, especially stream-idle gating.
- It said the next fact is whether the new `edge-decision-skip` patch compiles in the podman-backed WASM build.
- It said no better experiment exists before build viability.

## Decision

- Status: current
- Why: rerunning the exact same build with only sandbox escalation changed is a mechanical retry and changes only compile viability for the new diagnostic.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: compile first; keep the next runtime field as `edge_trace_marker_absence_reason` only after the build passes.

## Progress-Method Critique

- The critique said mechanical failures should not carry the same weight as semantic failures, but they still must be recorded under the repo rule.
- Suggested process adjustment: label these as mechanical retries and allow exactly one identical command retry with only sandbox/escalation changed after the required history and loop-check entry.

## Next Step

- Narrow follow-up: rerun the same podman-backed WASM build with sandbox escalation.
