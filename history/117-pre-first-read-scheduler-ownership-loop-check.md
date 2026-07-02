# Pre First Read Scheduler Ownership Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether
  `history/116` justifies a bounded emulation-thread deterministic scheduler
  design/code step before another browser runtime.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Read history/116 in addition to prior context. Evaluate the conclusion that
browser host-pump ownership is unstable because it runs from headless polling
with bql_try_lock and lands at different guest PCs; regular main-loop-wait
timer markers are absent from current browser artifacts; deterministic host
pumping can move browser_first_watch_read_ticks from 0 to 2 but breaks the
useful post-service edge; and the watched word is produced by guest tick-block
execution, not direct host timer callbacks. Answer the standard loop-check
questions, include Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Scheduler ownership inspection:
  `history/116-pre-first-read-scheduler-ownership-inspection.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_timer_delivery_owner`, then later
  `browser_first_watch_read_ticks` and post-service edge preservation.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping if we leave host-pump count tuning and exact-PC
  defer behind.
- It said we would be looping if the next step is another browser host-pump
  placement/count runtime.
- It accepted that `history/116` changed the boundary by identifying the
  ownership problem: browser headless polling is unstable because it lands at
  different guest PCs.
- The narrowest next fact is whether an emulation-thread-owned checkpoint can
  deliver expired PIT/PIC work and then let guest execution complete the tick
  block before the first watched read while preserving the baseline
  `0x80030e84->0x80030f31` edge.
- It killed browser headless host-pump ownership as the deterministic scheduler
  fix.
- It kept the fact that the watched word must be advanced by guest execution,
  not direct host timer writes.
- It revised deterministic scheduling toward pairing timer/IRQ delivery with
  bounded guest execution on an emulation-thread boundary, not from polling
  cadence or `bql_try_lock()` timing.
- It said a bounded emulation-thread deterministic scheduler checkpoint is
  justified as a design/code step before any runtime.
- It said a runtime is only justified after the checkpoint has precise guards:
  `browser_first_watch_read_ticks > 1` and preserved useful post-service edge.

## Decision

- Status: current.
- Why: the next action should inspect/design or implement one bounded
  emulation-thread scheduler checkpoint with named fields before any new
  browser runtime.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: do not vary host-pump counts, ready-edge placement,
  or exact-PC defer behavior for the next 2-3 turns. Make one bounded
  emulation-thread scheduler design/code step.

## Progress-Method Critique

- The critique said this remains connected to strict dashboard execution because
  it targets the tick/CPU ordering gap blocking browser-runtime
  `dashboard=xbe-executed`; visible main-menu proof and game launch still
  depend on that gate.
- It said the work was becoming too diagnostic-heavy during exact-PC defer and
  host-pump tuning, but the ownership inspection narrowed the next change.
- Process adjustment for the next 2-3 turns: one bounded emulation-thread
  scheduler design/code step with named fields before any new browser runtime.

## Next Step

- Narrow follow-up: inspect the CPU/main-loop boundary for a small opt-in
  emulation-thread checkpoint that dispatches expired timer work under normal
  ownership and lets guest execution advance the watched tick block, without
  hand-mutating interrupt state.
