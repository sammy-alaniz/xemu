# Defer Condition Lost Log Inspection

## Purpose

- One new fact this inspection was supposed to produce:
  `defer_condition_lost_reason`, the reason `history/106` saw hard IRQ state
  at the `0x80030e84` defer hook while `history/110` reached the same hook with
  `action=skip reason=no-hard-irq`.

## Command(s)

```sh
rg -n "tick-block-irq-defer|tick-block=complete|edge-decision context=browser-runtime|memory-watch context=browser-runtime seq=1|cpu=hard-irq-service context=browser-runtime|cpu=iret context=browser-runtime|main-loop=timers context=browser-runtime" \
  build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log

rg -n "tick-block-irq-defer|tick-block=complete|edge-decision context=browser-runtime|memory-watch context=browser-runtime seq=1|cpu=hard-irq-service context=browser-runtime|cpu=iret context=browser-runtime|main-loop=timers context=browser-runtime" \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

rg -n "tick_block_irq_defer|icount_decr|saved_icount|restored_icount|tick-block-irq-defer" \
  accel/tcg/cpu-exec.c xemu-xbe.c xemu-xbe.h

nl -ba accel/tcg/cpu-exec.c | sed -n '1040,1135p'
nl -ba accel/tcg/cpu-exec.c | sed -n '1135,1145p'
nl -ba xemu-xbe.c | sed -n '3590,3698p'
nl -ba xemu-xbe.c | sed -n '3780,3868p'

scripts/xbox-post-service-edge-decision-compare.py \
  --log effective=build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log \
  --log highhalf=build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log
```

## Inputs And Artifacts

- Effective-state combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log`
- High-half combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log`
- Source files inspected:
  `accel/tcg/cpu-exec.c`, `xemu-xbe.c`, and `xemu-xbe.h`
- Fixture assumptions: no-emulation log and source inspection only; no build,
  browser runtime, or code changes.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `defer_condition_lost_reason` and whether the tick-block IRQ-defer patch
  should be quarantined before further deterministic scheduler work.

## Findings

- Result: `defer_condition_lost_reason` is an ordering difference in when the
  bounded host timer pump injects the next hard IRQ relative to the
  `0x80014f32 -> 0x80030e84` return path.
- In the effective run, the third host timer progress event happened while CPU
  context was already at `eip=0x80030e84`:
  `main-loop=timers ... seq=3 ... eip=0x80030e84 ...
  cpu_interrupt_request=0x00000002 pending_interrupt=yes
  cpu_exit_request=yes`.
- Immediately after that, the defer hook saw the pending IRQ and engaged:
  `tick-block-irq-defer ... action=defer ...
  effective_interrupt_request=0x00000002 effective_exit_request=yes
  sample_mismatch=yes`.
- That effective run then restored the IRQ, serviced it at `0x80030e84`, IRETed
  back to `0x80030e84`, skipped a second defer because no hard IRQ remained,
  and completed the tick block at 0 -> 1 ticks.
- In the high-half run, the third host timer progress event happened earlier,
  while CPU context was still at `eip=0x80014f32`:
  `main-loop=timers ... seq=3 ... eip=0x80014f32 ...
  cpu_interrupt_request=0x00000002 pending_interrupt=yes
  cpu_exit_request=yes`.
- The CPU then reached `0x80030e84` as the interrupt-service entry point:
  `cpu=hard-irq-service ... phase=before ... eip=0x80030e84`, followed by
  `phase=after ... eip=0x80030e4c`.
- After IRET returned to `0x80030e84`, the hook finally ran, but the pending
  hard IRQ had already been consumed:
  `tick-block-irq-defer ... action=skip reason=no-hard-irq ...
  effective_interrupt_request=0x00000000 effective_exit_request=no`.
- Source placement confirms the hook is keyed only on `guest_pc ==
  XEMU_XBE_TICK_BLOCK_PC` inside `cpu_loop_exec_tb()` before `cpu_tb_exec()`.
  It can only defer an IRQ that is still pending when a TB starting exactly at
  `0x80030e84` is about to execute.
- Therefore the high-half patch did not get a chance to prove
  `first_deferred_tb_expected_path`: by the time the exact-PC hook saw the TB,
  the IRQ had already been serviced and IRET had returned.
- The edge-decision comparator reports both effective and highhalf as
  `post-service-edge-diverged` versus the active ready-edge host4 baseline.
  Effective has a later `0x80030e84->0x80030f31` block at 1 tick; highhalf has
  no first expected block in the comparator focus window. Neither improves
  `browser_first_watch_read_ticks`.

## Decision

- Status: current static diagnosis.
- Why: the IRQ-defer hook is too exact-PC and timing-sensitive to be the next
  scheduler fix. It can miss the relevant pending IRQ when timer delivery lands
  at the predecessor return block and the interrupt is serviced before the
  hook's exact `0x80030e84` pre-TB point.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: `history/111` required this no-emulation comparison
  before any new runtime or code change and explicitly blocked another
  tick-block IRQ-defer runtime.

## Progress-Method Critique

- This inspection still connects to the goal because it explains why a proposed
  deterministic execution tweak failed to move the strict dashboard execution
  boundary.
- The tick-block IRQ-defer slice should stop as a runtime-tuning path. It is
  now preserving a very narrow diagnostic that is sensitive to one-TB ordering
  and does not change the primary tick field.
- The history/loop-check process helped by forcing this static comparison
  instead of a third similar browser runtime.
- The next mode should be code cleanup/quarantine or a broader deterministic
  scheduler design, not another exact-PC defer experiment.
- Process adjustment for the next 2-3 turns: treat
  `browser_first_watch_read_ticks` and preservation of the baseline useful
  post-service edge as the only acceptable runtime promotion metrics; exact-PC
  IRQ-defer markers are explanatory only.

## Next Step

- Narrow follow-up: run the required loop check. The checkpoint should decide
  whether to quarantine/remove the opt-in tick-block IRQ-defer patch now, keep
  only harmless marker plumbing, or move directly to a deterministic scheduler
  boundary that targets timer delivery before the first watched read.
