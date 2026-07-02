# Tick Block IRQ Defer Quarantine

## Purpose

- One new fact this cleanup was supposed to produce:
  `tick_block_irq_defer_quarantined`, meaning the exact-PC IRQ-defer behavior
  can no longer alter CPU interrupt, exit-request, or TCG icount state.

## Command(s)

```sh
apply_patch <<'PATCH'
# Update xemu_xbe_boot_trace_tick_block_irq_defer_pre_tb() so enabled probes
# still emit a marker, but always use action=skip reason=quarantined and return
# false.
PATCH

git diff --check -- xemu-xbe.c

nl -ba xemu-xbe.c | sed -n '3636,3668p'
nl -ba xemu-xbe.c | sed -n '3740,3784p'
```

## Inputs And Artifacts

- Source file changed: `xemu-xbe.c`
- Prior critique:
  `history/113-defer-condition-lost-loop-check.md`
- Fixture assumptions: cleanup-only source edit; no build, no emulation run.

## Expected Field(s)

- Loop-guard field(s) this cleanup could change or explain:
  `tick_block_irq_defer_quarantined`.

## Findings

- Result: `xemu_xbe_boot_trace_tick_block_irq_defer_pre_tb()` now keeps the
  marker path but disables behavior:
  `reason = "quarantined";` and `active` remains false.
- The removed behavioral branch was the only path that could set `active =
  true`.
- Therefore the caller in `cpu_loop_exec_tb()` will not enter the block that
  resets interrupt state, clears `exit_request`, clears
  `cpu->neg.icount_decr.u16.high`, restores those fields, or emits the defer
  post marker.
- If the old opt-in knob is enabled in a future diagnostic, the pre marker
  should report `action=skip reason=quarantined` and then normal edge-decision
  tracing continues.
- `git diff --check -- xemu-xbe.c` passed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured in this cleanup-only step. No runtime behavior was exercised.

## Decision

- Status: current cleanup.
- Why: exact-PC IRQ deferral is no longer an active runtime fix candidate; this
  keeps the audit marker while preventing the dead-end behavior from affecting
  later deterministic scheduler work.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: `history/113` said further exact-PC defer code is
  justified only as cleanup/quarantine and the next runtime-worthy field must
  return to `browser_first_watch_read_ticks`, with post-service edge
  preservation as a guard.

## Progress-Method Critique

- This cleanup supports the final goal indirectly by removing a misleading path
  that did not move strict dashboard execution toward the browser main menu or
  game launch.
- It is not a runtime improvement; it is process hygiene so future experiments
  do not keep reusing a failed exact-PC mechanism.
- The history/loop-check process helped force a stop condition for the
  micro-scheduler slice.
- The next mode should be deterministic scheduler design/inspection around
  timer delivery before the first watched read, not another tick-block defer
  run.
- Process adjustment for the next 2-3 turns: name
  `browser_first_watch_read_ticks` or a direct prerequisite to it before any
  new runtime work.

## Next Step

- Narrow follow-up: run the required bounded loop check. If it agrees, inspect
  where to own deterministic timer delivery before the first watched read while
  preserving the active baseline post-service edge.
