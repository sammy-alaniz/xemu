# Emulation Thread Checkpoint Site Inspection

## Purpose

- One new fact this inspection was supposed to produce:
  `emulation_thread_checkpoint_site`, the specific CPU/main-loop boundary where
  an opt-in deterministic scheduler checkpoint could deliver expired timer work
  without hand-mutating interrupt state.

## Command(s)

```sh
rg -n "memory_watch|watch_read|watch_write|access_filter|memory-watch|exec_tick_block|exec_edge_decision|first_watch|watch_phys" \
  xemu-xbe.c xemu-xbe.h

nl -ba xemu-xbe.c | sed -n '80,150p'
nl -ba xemu-xbe.c | sed -n '3160,3565p'
nl -ba accel/tcg/cpu-exec.c | sed -n '1036,1178p'

rg -n "cpu_exec_loop|cpu_handle_interrupt|while.*cpu_exec|cpu_loop_exec_tb|EXCP_INTERRUPT|cpu_handle_exception" \
  accel/tcg/cpu-exec.c

nl -ba accel/tcg/cpu-exec.c | sed -n '720,930p'
nl -ba accel/tcg/cpu-exec.c | sed -n '1178,1265p'
nl -ba xemu-xbe.c | sed -n '1250,1510p'

rg -n "TCG_TIMER_PUMP_IDLE_LOOP_PC|TICK_BLOCK_PC|EDGE_DECISION|0x80014f32|0x80014f5f|0x8001b02f|0x8001b030|0x80030e84" \
  xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c

nl -ba xemu-xbe.c | sed -n '40,88p'
nl -ba xemu-xbe.c | sed -n '1500,1788p'
nl -ba xemu-xbe.c | sed -n '6340,6428p'
```

## Inputs And Artifacts

- Source files inspected:
  `accel/tcg/cpu-exec.c`, `xemu-xbe.c`, and `xemu-xbe.h`
- Prior scheduler ownership summary:
  `history/116-pre-first-read-scheduler-ownership-inspection.md`
- Fixture assumptions: no-emulation source inspection only; no code changes.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `emulation_thread_checkpoint_site`, a direct prerequisite for
  `browser_first_watch_read_ticks`.

## Findings

- Result: the best existing ownership site is the TCG CPU execution loop, not
  browser headless polling.
- `cpu_exec_loop()` repeatedly calls `cpu_handle_interrupt()` before selecting
  and executing a TB. If a timer callback sets `CPU_INTERRUPT_HARD` and kicks
  the vCPU, normal QEMU interrupt handling can service it on the next loop.
- `cpu_loop_exec_tb()` already has an opt-in TCG timer pump call after
  `cpu_tb_exec()` by default:
  `if (!xemu_tcg_timer_pump_before_tb) { xemu_boot_trace_tcg_timer_pump(); }`.
- That pump is emulation-thread-owned rather than browser-host-loop-owned. It
  can run expired virtual timers, then return to the normal CPU loop where
  `cpu_handle_interrupt()` clears the icount high half, handles
  `exit_request`, and dispatches hard IRQs without manual interrupt masking.
- The existing TCG pump can also run before a TB for the old
  `pit-before-pfifo-transition-activity-pre-tb-defer` mode, but that exact
  pre-TB/defer family is historical negative territory. The safer design is
  after-TB timer delivery followed by normal QEMU interrupt service.
- The current TCG readiness helpers are idle/PFIFO-transition oriented:
  `idle-loop`, `idle-loop-serviceable`, `pit-after-idle`,
  `pit-after-idle-full`, `pit-after-pfifo-transition`, and several
  before-PFIFO-transition modes.
- None of those modes directly express the current target: after PFIFO
  stream-idle, before the first watched read, with bounded guest execution until
  a normal `tick-block=complete` is observed.
- The watched word state is already tracked through
  `exec_tick_block_probe_count`, `exec_tick_block_pre_stream_count`, and
  `tick-block=complete` markers. This gives a natural stop condition for a
  later checkpoint: stop after a bounded number of TCG timer deliveries or once
  the normal guest tick block completes.
- The checkpoint should not mutate `interrupt_request`, `exit_request`, or
  `cpu->neg.icount_decr.u16.high` by hand. The exact-PC IRQ-defer slice showed
  that path is too fragile.

## Decision

- Status: current design inspection.
- Why: the next implementable unit is a small opt-in TCG pump readiness mode or
  checkpoint that runs from `cpu_loop_exec_tb()` after TB execution, uses normal
  timer callbacks and normal CPU interrupt handling, and is gated by the
  post-PFIFO/pre-first-read state.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/117` approved one bounded
  emulation-thread scheduler design/code step and said not to vary host-pump
  counts, ready-edge placement, or exact-PC defer behavior.

## Progress-Method Critique

- This still moves toward strict dashboard execution because it identifies a
  scheduler ownership point that can plausibly change
  `browser_first_watch_read_ticks`, the current prerequisite for
  `dashboard=xbe-executed`.
- It avoids another runtime rerun and avoids returning to exact-PC defer.
- This is close to enough inspection; another broad source-reading pass would
  become diagnostic-heavy.
- The next mode should be a bounded code design or patch, with explicit guards:
  target `browser_first_watch_read_ticks > 1`, preserve
  `0x80030e84->0x80030f31`, and keep strict B6 unchanged.
- Process adjustment for the next 2-3 turns: implement at most one new opt-in
  emulation-thread checkpoint mode before any runtime validation.

## Next Step

- Narrow follow-up: run the required loop check. If it approves, add one opt-in
  TCG timer pump mode/checkpoint that targets post-PFIFO/pre-first-read
  delivery and relies on normal CPU interrupt handling rather than manual IRQ
  deferral.
