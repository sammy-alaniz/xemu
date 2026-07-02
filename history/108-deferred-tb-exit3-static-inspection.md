# Deferred TB Exit3 Static Inspection

## Purpose

- One new fact this inspection was supposed to produce:
  `deferred_tb_exit3_source`, the reason the deferred `0x80030e84` TB still
  returned `tb_exit=3` with next PC unchanged after the one-TB IRQ defer cleared
  `CPU_INTERRUPT_HARD` and `exit_request`.

## Command(s)

```sh
rg -n "cpu_tb_exec|TB_EXIT_REQUESTED|exit_request|EXIT_REQUESTED|tb_exit|CF_LAST_IO|icount_exit_request|cpu_loop_exit_requested|cpu_exec_step_atomic|set_jmp|cpu_loop_exit" \
  accel/tcg include/tcg include/exec target/i386 -g '*.[ch]'

sed -n '780,940p' accel/tcg/cpu-exec.c
sed -n '940,1025p' accel/tcg/cpu-exec.c
sed -n '1025,1125p' accel/tcg/cpu-exec.c
sed -n '970,1000p' include/tcg/tcg.h

rg -n "exitreq_label|exit_request|icount_decr|gen_tb_end|tcg_gen_exit_tb\\(.*TB_EXIT_REQUESTED|gen_io_start|can_do_io|CF_NOIRQ|CF_USE_ICOUNT" \
  accel/tcg target/i386 include -g '*.[ch]'

sed -n '1,130p' accel/tcg/translator.c
sed -n '130,245p' accel/tcg/translator.c
sed -n '1120,1260p' accel/tcg/cpu-exec.c

nl -ba accel/tcg/translator.c | sed -n '45,82p'
nl -ba accel/tcg/translator.c | sed -n '96,106p'
nl -ba accel/tcg/cpu-exec.c | sed -n '846,858p'
nl -ba accel/tcg/cpu-exec.c | sed -n '884,891p'
nl -ba include/tcg/tcg.h | sed -n '982,1012p'
```

## Inputs And Artifacts

- Latest runtime log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1/browser-runtime.log`
- Latest combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log`
- Source files inspected:
  `accel/tcg/cpu-exec.c`, `accel/tcg/translator.c`, `include/tcg/tcg.h`,
  `include/exec/cpu-common.h`, and related TCG search results.
- Fixture assumptions: static source inspection only; no build or runtime state
  changes.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `deferred_tb_exit3_source` and `first_deferred_tb_expected_path`.

## Findings

- Result: the most likely source of the deferred TB's `tb_exit=3` is the TCG
  generated exit-request check using `cpu->neg.icount_decr.u32`, specifically
  the high half set negative by `tcg_kick_vcpu_thread()`.
- `include/tcg/tcg.h` defines `TB_EXIT_REQUESTED=3` and documents it as a TB
  not started because the CPU's exit request was noticed.
- `accel/tcg/translator.c` loads `CPUState.neg.icount_decr.u32` at TB start
  when interrupts are not suppressed, branches to `exitreq_label` if that
  signed value is negative, and emits `tcg_gen_exit_tb(tb,
  TB_EXIT_REQUESTED)` at that label.
- `tcg_kick_vcpu_thread()` sets both `cpu->exit_request=true` and
  `cpu->neg.icount_decr.u16.high=-1`.
- Normal `cpu_handle_interrupt()` clears `cpu->neg.icount_decr.u16.high` before
  reading `exit_request` or `interrupt_request`.
- The current one-TB defer happens after `cpu_handle_interrupt()` and after a
  host timer pump has set a new pending IRQ at `eip=0x80030e84`. It clears
  `CPU_INTERRUPT_HARD` and `cpu->exit_request`, but it does not clear
  `cpu->neg.icount_decr.u16.high`.
- This matches `history/106`: the deferred TB's post marker had
  `post_interrupt_request=0x00000000` and `post_exit_request=no`, but still
  `tb_exit=3` and `expected_path=no`, meaning the TB likely exited through the
  generated `exitreq_label` before executing.

## Decision

- Status: current static diagnosis.
- Why: the next code candidate is now specific: if the micro-scheduler slice
  continues, the one-TB defer must also clear the TCG exit-request high half
  for that one block, not just `exit_request` and `CPU_INTERRUPT_HARD`.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: `history/107` required code inspection and said
  another runtime was not justified until `deferred_tb_exit3_source` was
  explained.

## Progress-Method Critique

- This inspection still connects to strict browser dashboard execution because
  it explains why the one-TB scheduler could not test the intended guest block
  execution path.
- It is narrowly diagnostic, but not a rerun: it changes the causal field from
  "hard IRQ still pending" to "TCG exit-request high half still negative."
- The history/loop-check process helped by preventing another ineffective
  ready-edge runtime.
- The right next mode depends on the required loop check: either apply a very
  small code change to clear/restore `neg.icount_decr.u16.high` in the one-TB
  defer, or abandon the IRQ-defer micro-scheduler if that is judged too
  invasive.
- Process adjustment for the next 2-3 turns: any next validation must be judged
  on `first_deferred_tb_expected_path`, not just `irq_defer_engaged`.

## Next Step

- Narrow follow-up: run the required loop check. If it approves continuing this
  slice, patch the one-TB defer to clear the TCG exit-request high half in the
  same bounded critical section and log before/post/restored high-half values.
