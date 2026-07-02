# Pre-First-Read Post-STI Pump Loop Check

## Purpose

- One new fact this run was supposed to produce: whether the audited exact-PC post-STI timer-pump code change is justified.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest static/log audit `history/162-pre-first-read-serviceable-window-audit.md`
- rejection of broadening to `0x80014f3d`
- proposed exact condition for `0x80014f32` with IF set and IRQ inhibition set
- proposed field `post_sti_first_read_predecessor_timer_pump`
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Gate-marker browser log: `build-real-b3-matrix/browser-pre-first-read-entry-ready-gate-v1/browser-runtime.log`
- Prior history entry: `history/162-pre-first-read-serviceable-window-audit.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_first_read_predecessor_timer_pump`.

## Findings

- Result: continue.
- Are we looping? No, if the next step is the exact targeted code revision from the audit.
- Narrowest next fact: `post_sti_first_read_predecessor_timer_pump`.
- Kill: broadening to `0x80014f3d`; it is a pre-stream-idle, wrong-branch point.
- Keep: broad IRQ-inhibited states should remain rejected; strict B6 must remain real.
- Revise: special-case only `0x80014f32` under audited conditions, and focus gate-marker emission on stream-idle or exact candidate PCs.
- Code revision justified now? Yes.
- Better experiment? None before the code change; the static audit already identified the exact PC/state.
- Progress-method critique: the metrics still connect to strict dashboard execution because the browser first-read tick gap blocks real `dashboard=xbe-executed`; visible main-menu proof and game launch remain downstream. The work is diagnostic-heavy, but the latest audit produced a concrete, narrow code target. The next mode should be code change.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: the patch must encode the audited condition literally: `pc=0x80014f32`, IF set, IRQ inhibited, no pending interrupt, post-stream-idle or exact candidate marker gating, and no expansion to other inhibited states.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: continue with a narrow code change only; no runtime probing until after build and a follow-up loop check.

## Next Step

- Narrow follow-up: patch the serviceable predicate and marker filter for the exact post-STI first-read predecessor condition, then build.
