# Tick Block IRQ Defer Quarantine Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the quarantine
  cleanup in `history/114` is sufficient before returning to deterministic
  scheduler design.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Read history/114 in addition to prior context. Evaluate the cleanup:
xemu_xbe_boot_trace_tick_block_irq_defer_pre_tb keeps the pre marker but always
reports reason=quarantined with active=false, so the caller cannot reset
interrupts, clear exit_request, clear icount high-half, restore them, or emit
the post defer marker. Answer the standard loop-check questions, include
Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Cleanup summary:
  `history/114-tick-block-irq-defer-quarantine.md`
- Prior loop check:
  `history/113-defer-condition-lost-loop-check.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `tick_block_irq_defer_quarantined` and the next direct scheduler prerequisite
  for `browser_first_watch_read_ticks`.

## Findings

- Result: critique decision was `continue`.
- It said the exact-PC IRQ-defer loop is stopped if the quarantine is accepted.
- It said we would only be looping again if the next step returned to another
  `tick-block-irq-defer` runtime or more exact-PC defer behavior.
- The next useful fact is where deterministic timer/IRQ delivery should be
  owned before the first watched read so `browser_first_watch_read_ticks` can
  move above 0 while preserving the active baseline's useful post-service edge.
- It killed exact-PC `0x80030e84` IRQ deferral as a fix.
- It kept browser pre-service tick accumulation as the live boundary: 0 ticks
  versus native 136.
- It revised scheduler work toward deterministic ordering before the
  `0x80014f32->0x80030e84` first-read path.
- It said the quarantine is sufficient before scheduler design because the
  marker remains auditable and `active=false` prevents mutation of interrupt
  state, `exit_request`, or icount high-half state.
- It recommended inspecting/designing the deterministic scheduler ownership
  point for host timer delivery relative to the first watched read: CPU loop,
  main-loop timer dispatch, or browser host pump boundary.

## Decision

- Status: current.
- Why: the exact-PC defer path is quarantined and no further cleanup is needed
  unless a build or mechanical issue appears.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: do not touch tick-block defer except to resolve
  mechanical build fallout. Name `browser_first_watch_read_ticks` or a direct
  scheduler prerequisite before any new runtime or code change.

## Progress-Method Critique

- The critique said this remains connected to strict dashboard execution
  because we are returning to the tick gap that blocks `dashboard=xbe-executed`,
  which gates visible main-menu proof and game launch.
- It said the defer branch became too diagnostic-heavy, but the quarantine is a
  useful stop condition rather than another rerun.
- Process adjustment for the next 2-3 turns: inspect deterministic scheduler
  ownership, not exact-PC defer behavior.

## Next Step

- Narrow follow-up: inspect where browser deterministic timer/IRQ delivery
  should be owned before the first watched read, targeting
  `browser_first_watch_read_ticks` with post-service edge preservation as a
  guard.
