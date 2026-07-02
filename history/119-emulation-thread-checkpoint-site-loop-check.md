# Emulation Thread Checkpoint Site Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether
  `history/118` justifies one opt-in TCG checkpoint mode before any new browser
  runtime.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Read history/118 in addition to prior context. Evaluate the conclusion that the
best ownership site is the TCG CPU loop after cpu_tb_exec(), where an opt-in
TCG timer pump can run expired virtual timers and normal cpu_handle_interrupt()
can service pending IRQs on the next loop; current TCG modes are idle/PFIFO
transition oriented and do not directly express post-PFIFO/pre-first-read
bounded guest tick-block completion; exact-PC IRQ defer must remain dead.
Answer the standard loop-check questions, include Progress-Method Critique,
and end with one decision.
```

## Inputs And Artifacts

- Checkpoint site inspection:
  `history/118-emulation-thread-checkpoint-site-inspection.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_tcg_checkpoint_active`, then later
  `browser_first_watch_read_ticks` and post-service edge preservation.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping if the next step is a single opt-in TCG checkpoint
  design/patch, not another host-pump or exact-PC defer variant.
- It accepted that `history/118` changed the boundary by identifying an
  emulation-thread-owned site after `cpu_tb_exec()` in the TCG loop.
- The narrowest next fact is whether a post-PFIFO/pre-first-read TCG checkpoint
  can run expired virtual timers from the emulation thread and then let normal
  `cpu_handle_interrupt()` advance guest execution to a normal
  `tick-block=complete` before the first watched read.
- It killed exact-PC IRQ defer and manual mutation of `interrupt_request`,
  `exit_request`, or icount high-half.
- It kept that the watched word advances through guest tick-block execution,
  while timer callbacks only set up normal interrupt delivery.
- It revised the existing TCG pump modes as insufficient because they are
  idle/PFIFO-transition oriented.
- It said one opt-in TCG checkpoint mode/checkpoint is justified before a
  runtime, with clear guards: `browser_first_watch_read_ticks > 1`, preserved
  `0x80030e84->0x80030f31`, and no weakening of strict B6.
- Recommended implementation shape: add one diagnostic-only TCG pump mode in
  the existing after-`cpu_tb_exec()` path, gate it to post-PFIFO/pre-first-read
  state, cap timer deliveries, stop once normal `tick-block=complete` is
  observed, and rely on the next CPU loop's normal `cpu_handle_interrupt()`.

## Decision

- Status: current.
- Why: the next action is a bounded code step to add exactly one opt-in
  emulation-thread checkpoint mode before runtime validation.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: implement at most one opt-in TCG checkpoint mode
  before runtime validation. Do not broaden into host polling, pump counts,
  PFIFO rediscovery, or exact-PC defer cleanup.

## Progress-Method Critique

- The critique said this method is still moving toward strict dashboard
  execution because it targets the scheduler/tick gap blocking browser-runtime
  `dashboard=xbe-executed`; main-menu proof and game launch remain gated behind
  that.
- It said the exact-PC defer phase was diagnostic-heavy, but the current
  inspection is specific enough to justify one code step.
- Process adjustment for the next 2-3 turns: one opt-in TCG checkpoint mode,
  then validation only against the named fields.

## Next Step

- Narrow follow-up: implement one diagnostic-only TCG checkpoint mode that runs
  after `cpu_tb_exec()`, is gated to post-PFIFO/pre-first-read state, caps timer
  deliveries, stops after normal `tick-block=complete`, and does not manually
  mutate CPU interrupt state.
