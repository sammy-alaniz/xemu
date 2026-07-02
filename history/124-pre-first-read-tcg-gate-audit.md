# Pre First Read TCG Gate Audit

## Purpose

- One new fact this audit was supposed to produce:
  `pre_first_read_tcg_gate_blocker`, the exact readiness predicate that kept
  `pit-post-pfifo-pre-first-read` from emitting `BOOT_MARK b6 tcg=timer-pump`
  before the first watched read.

## Command(s)

```sh
rg -n "tcg_timer_pump_post_pfifo|tcg_timer_pump_ready|tcg_timer_pump_pit_only|xemu_xbe_exec_context_is_idle_loop_serviceable|exec_tick_block_probe_count|exec_edge_decision_probe_count|timer-pump" xemu-xbe.c

sed -n '1400,1565p' xemu-xbe.c
sed -n '1840,1985p' xemu-xbe.c
sed -n '6360,6465p' xemu-xbe.c

sed -n '960,1035p' accel/tcg/cpu-exec.c
sed -n '1085,1150p' accel/tcg/cpu-exec.c
rg -n "xemu_boot_trace_tcg_timer_pump\\(|xemu_xbe_boot_trace_observe_exec|observe_exec" accel/tcg/cpu-exec.c

sed -n '2618,2660p' build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log
rg -n "BOOT_MARK b6 dashboard=kernel-loop-probe context=browser-runtime observed_seq=(1|2|3|4|5|6|7) .*probe=after-idle-transition-sample" build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log
rg -n "BOOT_MARK b6 tcg=timer-pump|tcg=timer-pump-gate|pit-post-pfifo-pre-first-read" build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log tcg=build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log

sed -n '3740,3780p' build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
sed -n '70,90p' xemu-xbe.c
```

## Inputs And Artifacts

- Native reference log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Active browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- TCG runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log`
- Source inspected:
  `xemu-xbe.c`, `accel/tcg/cpu-exec.c`
- Fixture assumptions: no emulation rerun and no code edits; this is a
  source/log audit only.

## Expected Field(s)

- Loop-guard field(s) this audit could change or explain:
  `pre_first_read_tcg_gate_blocker`, `pre_first_read_tcg_checkpoint_active`,
  `browser_first_watch_read_ticks`, and `browser_post_service_top_edge`.

## Findings

- Result: `pre_first_read_tcg_gate_blocker=idle-loop-pc-only-gate`.
- `xemu_xbe_tcg_timer_pump_post_pfifo_pre_first_read_ready()` requires:
  positive after-idle limit, delivery attempts below limit, PFIFO stream-idle
  transition observed, no `tick-block=complete`, no `edge-decision`, current
  wait state PFIFO-empty, `xemu_xbe_exec_context_is_idle_loop_serviceable()`,
  and virtual timers present/expired.
- The serviceable helper is stricter than the pre-read slice needs. It requires
  protected32 CPL0 with IF set, no `HF_INHIBIT_IRQ_MASK`, no pending interrupt,
  and `pc == XEMU_XBE_TCG_TIMER_PUMP_IDLE_LOOP_PC_2`, which is
  `0x8001b030`.
- The TCG call site is after `cpu_tb_exec()`,
  `edge_decision_post_tb()`, `tick_block_post_tb()`, and
  `observe_exec_transition()` for the just-finished TB.
- In the browser runtime, the useful pre-read checkpoint occurs after
  `0x80014f32->0x80030e84` at line 2644. At that point the next instruction is
  the watched read of physical `0x0003a890`; the CPU has no pending interrupt,
  no IRQ inhibition, PFIFO is empty, and the watched value is still 0.
- That useful checkpoint is rejected because the PC is `0x80030e84`, not
  `0x8001b030`.
- Earlier post-PFIFO checkpoints are rejected for real CPU-context reasons:
  `0x80018e07` has a pending hard IRQ, `0x80014f2d` and `0x80014f31` have IF
  clear, and `0x80014f32` has `irq_inhibited=yes`.
- The requested mode was applied, but no `BOOT_MARK b6 tcg=timer-pump` marker
  appeared in the TCG artifact.
- Native confirms the same broad boundary shape: before the first watched read,
  native reaches a pre-read/tick-block checkpoint at `0x80030e84` with the
  watched word already nonzero, while browser reaches `0x80030e84` with the
  watched word still zero.
- The pre-service comparator still reports browser 0 ticks versus native 136.
- The post-service comparator still classifies the TCG artifact as
  `post-service-edge-diverged`; the active baseline remains the useful
  post-service edge artifact.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured by a new runtime. This audit used only existing artifacts.

## Decision

- Status: current diagnostic result.
- Why: the closed gate is explained without another browser run. The current
  `pit-post-pfifo-pre-first-read` mode is aimed at the prior idle-loop PC
  hypothesis, but the actionable pre-read checkpoint for this slice is
  `0x80030e84`.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: `history/123` required a source/log audit before
  any rerun. This audit found the blocker requested by that critique.

## Progress-Method Critique

- This inspection moved toward strict browser dashboard execution by replacing
  a broad failed runtime result with one exact source/log blocker.
- The work is still diagnostic, but it is not rerun-heavy here: no new
  emulation was started, and the audit directly answered the named field.
- The method should now shift from more inspection to one small code revision
  if the loop check agrees: allow a bounded pre-read/tick-block checkpoint at
  `0x80030e84`, without weakening strict B6 and without manual interrupt state
  mutation.
- Process adjustment for the next 2-3 turns: before editing, name the exact
  predicate being changed as `pc == 0x80030e84` under the already-audited
  PFIFO-empty/no-edge/no-tick/no-pending/no-inhibit conditions, and keep the
  active baseline as the fallback if the run regresses the post-service edge.

## Next Step

- Narrow follow-up: run the required loop check. If approved, revise only the
  TCG gate predicate for `pit-post-pfifo-pre-first-read` so it can fire at the
  pre-read/tick-block PC `0x80030e84` under the existing bounded conditions.
