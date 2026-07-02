# Edge Decision Progress Method Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue with another runtime, revise the edge-decision diagnostic, or stop, while also critiquing whether our overall method is producing useful progress.

## Command(s)

```text
Spawned read-only sub-agent 019f1dfd-0a7e-7fb0-acfb-2d1d23d458cc with this checkpoint:

Read goal.md and recent history 78-82. Answer the standard loop-check
questions, then add a Progress-Method Critique covering whether the methods are
too diagnostic-heavy, whether the chosen fields still move toward browser
dashboard execution/main menu/game launch, whether history/loop-check rules are
helping or slowing the work, and one process adjustment for the next 2-3 turns.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log`
- Latest combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1-combined.log`
- Latest run summary: `history/82-edge-decision-readyedge-runtime.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: `edge_trace_marker_absence_reason`, `browser_post_service_top_edge`, and whether the next action should be a code inspection/revision instead of another runtime.

## Findings

- Result: critique decision was `revise`.
- The checkpoint said another runtime with the same edge-decision knobs would be looping.
- The narrowest next fact is whether the edge-decision hook is gated out or perturbing flow.
- It pointed to the current hook as too narrow: it captures only `guest_pc == 0x80030e84` and then requires `xemu_xbe_nv2a_wait_is_stream_idle()`.
- It connected that directly to history 82: the write at `eip=0x80030e84` occurred with `stream_idle=no` and wait `pcrtc/vblank-suppress`, so marker absence is explainable by the stream-idle gate.
- It killed fixture-plumbing failure, kept edge-decision tracing as aimed at a real boundary, and revised the current hook as too narrow and possibly perturbing because it performs pre-TB context/code/memory reads.
- Proposed better experiment/design: define a lower-impact marker that logs why the hook skipped, especially `skip_pc`, `skip_stream_idle`, `wait_source`, and `wait_op`, without doing memory/code reads first.

## Decision

- Status: current
- Why: the next work should explain `edge_trace_marker_absence_reason` by inspecting/revising the edge-decision hook before any more runtime runs.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: avoid another same-knob runtime; revise the diagnostic so a future run can distinguish `PC not reached`, `stream-idle gate false`, and `probe perturbed flow`.

## Progress-Method Critique

- The critique said the work is diagnostic-heavy but currently necessary; the risk is diagnostics perturbing the scheduler/CPU boundary being measured.
- It said the active fields still point toward browser dashboard execution because `browser_post_service_top_edge`, `browser_first_watch_read_ticks`, and strict `browser_dashboard_xbe_executed` are prerequisites for main menu and game launch.
- It warned against spending more turns on fields that only reconfirm B4/B5/read/load.
- It said history and loop checks are helping prevent blind reruns but can slow setup-only retries. Suggested process adjustment: allow one immediate mechanical retry for setup-only failures while still requiring history before semantic reruns or code changes.
- For the next 2-3 turns, consolidate around one field: `edge_trace_marker_absence_reason`.

## Next Step

- Narrow follow-up: inspect and revise the edge-decision hook so it can emit a low-impact skip/absence reason without doing pre-TB memory/code/context probes unless the gate passes.
