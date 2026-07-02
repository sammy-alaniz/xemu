# Defer Condition Lost Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether
  `history/112` justifies any further exact-PC tick-block IRQ-defer work, or
  whether the slice should be quarantined before returning to the broader
  deterministic scheduling boundary.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Read history/112 in addition to the prior context. Evaluate its conclusion that
the defer condition disappeared because the high-half run delivered the pending
hard IRQ while CPU was still at 0x80014f32, serviced it at 0x80030e84, and only
then reached the exact-PC defer hook after IRET with no hard IRQ pending.
Answer the standard loop-check questions, include Progress-Method Critique,
and end with one decision.
```

## Inputs And Artifacts

- Static/log inspection summary:
  `history/112-defer-condition-lost-log-inspection.md`
- Prior loop check:
  `history/111-tick-block-irq-defer-highhalf-loop-check.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `tick_block_irq_defer_quarantined`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: critique decision was `revise`.
- It said we are looping on the tick-block IRQ-defer path: this slice has now
  consumed an effective-state runtime, TCG high-half inspection, high-half
  runtime, and log inspection without moving `browser_first_watch_read_ticks`,
  preserving the active baseline post-service edge, or producing
  `dashboard=xbe-executed`.
- It said the narrowest useful next fact is no longer inside the exact-PC defer
  hook. The next scheduler fact is where deterministic timer delivery should be
  owned so browser accumulates ticks before the first watched read at
  `0x80014f32->0x80030e84`, without depending on whether a pending IRQ survives
  until a TB starts exactly at `0x80030e84`.
- It killed exact-PC tick-block IRQ defer as a runtime fix.
- It kept browser pre-service tick accumulation as the primary boundary:
  browser first read remains 0 ticks while native is 136.
- It revised the scheduler hypothesis from "defer one IRQ at `0x80030e84`" to
  "make timer/IRQ delivery deterministic before the first watched read while
  preserving the useful post-service edge."
- It said another tick-block IRQ-defer runtime is not justified by the loop
  guard. Further exact-PC defer code is justified only as cleanup/quarantine,
  not as a new behavioral experiment.

## Decision

- Status: current.
- Why: the next action should be cleanup/quarantine of the opt-in
  tick-block IRQ-defer path, or a design/code-inspection step for deterministic
  scheduling before the first watched read.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: stop exact-PC defer work. A cleanup-only step can
  change `tick_block_irq_defer_quarantined`; the next runtime-worthy field must
  return to `browser_first_watch_read_ticks`, with post-service edge
  preservation as a guard.

## Progress-Method Critique

- The critique said the current method still connects to strict dashboard
  execution because it focuses on the ordering gap blocking
  `dashboard=xbe-executed`, but this particular slice is now too
  diagnostic-heavy.
- It said exact-PC defer work explains a narrow failure mode without improving
  the primary metric.
- It recommended stopping exact-PC defer work for the next 2-3 turns.
- Process adjustment: either quarantine the patch or move to a broader
  deterministic scheduling design whose first stated field is
  `browser_first_watch_read_ticks`, with post-service edge preservation as a
  required guard.

## Next Step

- Narrow follow-up: make a cleanup-only change that quarantines/removes the
  exact-PC tick-block IRQ-defer behavior so future work can return to the
  deterministic scheduler boundary.
