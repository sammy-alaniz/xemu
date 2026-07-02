# Watch Word Producer Static Inspection

## Purpose

- One new fact this probe was supposed to produce: whether
  `browser_first_watch_read_ticks` is blocked by missing host timer callbacks,
  by the guest producer of physical `0x0003a890`, or by CPU/interrupt ordering
  before the first watched read.

## Command(s)

```sh
rg -n "0x0003a890|3a890|memory-watch|edge-decision|watch_read|watch_write|MEMORY_WATCH" \
  xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c scripts ui util hw include browser -g '!build*'
rg -n "headless=timer-pump-step-count|main-loop=timers context=browser-runtime|memory-watch context=browser-runtime|edge-decision context=browser-runtime|interrupt=service|interrupt=iret|pfifo=stream-idle" \
  build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log
sed -n '3160,3565p' xemu-xbe.c
sed -n '3690,3825p' xemu-xbe.c
sed -n '560,835p' ui/xemu-headless.c
sed -n '940,1135p' xemu-xbe.c
sed -n '5480,5685p' xemu-xbe.c
sed -n '660,725p' util/main-loop.c
nl -ba build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log | sed -n '2620,2678p'
nl -ba build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | sed -n '2488,2590p'
nl -ba build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | sed -n '3748,3762p'
rg -n "tcg_timer_pump|xemu_xbe_boot_trace_tcg|observe_tcg|qemu_clock_run_timers_with_attrs_limit|qemu_clock_run_all_timers|cpu_exec|cpu_loop_exec_tb|cpu_tb_exec|xemu_xbe_boot_trace_observe_exec" \
  accel/tcg target/i386 system util xemu-xbe.c xemu-xbe.h -g '!build*'
sed -n '940,1085p' accel/tcg/cpu-exec.c
sed -n '1,380p' hw/timer/i8254.c
sed -n '700,955p' accel/tcg/cpu-exec.c
sed -n '150,230p' target/i386/tcg/system/seg_helper.c
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log`
- Fixture assumptions: static code/log inspection only; no new runtime and no
  fixture changes.

## Expected Field(s)

- Loop-guard field(s) this probe could change or explain:
  `browser_first_watch_read_ticks`

## Findings

- Result: the watched word is produced by guest CPU execution, not by a host
  timer callback directly writing low RAM.
- The memory-watch callback is attached to `xbox.ram` at physical
  `0x0003a890` and records `value_phase=pre-access`, so write markers are guest
  writes that are about to happen.
- The edge-decision decode shows the block at `0x80030e84` begins with
  `mov-r32-rm32`, reading virtual `0x8003a890` mapped to physical
  `0x0003a890`.
- Browser ready-edge-host4 reaches the first watched read at
  `0x80014f32->0x80030e84` with value `0x00000000`, then the write callback at
  `eip=0x80030e84` also sees the pre-access value `0x00000000`.
- Native reaches the comparable post-idle read at
  `0x80014f5f->0x80030e84` with value `0x0014c080`, which is 136 tick units.
- `xemu_headless_pump_browser_timers()` and the TCG timer pump call
  `qemu_clock_run_timers_with_attrs_limit()`; those callbacks can assert or
  deassert PIT/PIC interrupt state, but they do not execute the guest tick
  block.
- The PIT path is `pit_irq_timer()` -> `pit_irq_timer_update()` ->
  `qemu_set_irq()` -> `timer_mod()`. It schedules/sets interrupt state; CPU
  execution must then dispatch the hard IRQ and run the guest handler.
- In the steps=2 runtime, extra ready-edge timer callbacks appear while the CPU
  is at `0x80030e4c` or `0x80014f32`, but the watched word remains zero because
  the guest tick-update block has not completed before the first watched read.
- The extra callbacks stack pending interrupt state and regress the useful edge
  shape instead of moving the first read toward native.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new
  runtime was started in this probe; the inspection explains the previous
  regression from `history/98`.

## Decision

- Status: current
- Why: this explains why raising ready-edge timer callback count did not move
  `browser_first_watch_read_ticks`. The missing piece is ordered guest execution
  of the tick block before the first dashboard/post-idle read, not another raw
  host timer callback.
- Independent critique used: no
- If yes, critique decision: n/a
- If yes, critique summary: n/a

## Progress-Method Critique

- The metric still connects to the main goal: strict dashboard execution is the
  prerequisite for main-menu and game launch, and the zero-tick first read is a
  current causal clue for why strict browser execution is missing.
- This probe reduced over-diagnostics by converting a vague timer-count problem
  into a producer/order problem.
- The history process helped here because `history/99` blocked another
  ready-edge step-count runtime and forced the static producer inspection.
- The right next mode is a loop-check, then either a small code change that
  exposes completed `0x80030e84` tick-block counts before stream-idle or a
  deterministic scheduling change that pairs PIT delivery with guest execution.
- Process adjustment for the next 2-3 turns: require the next proposed runtime
  to name whether it changes `pre_stream_tick_block_completions` or the actual
  ordered handoff between PIT/PIC interrupt delivery and guest tick-block
  execution.

## Next Step

- Narrow follow-up: run the required sub-agent loop check with the new
  `Progress-Method Critique` requirement before any next code change or
  runtime.
