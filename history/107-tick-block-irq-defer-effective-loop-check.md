# Tick Block IRQ Defer Effective Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the effective
  IRQ-defer result in `history/106` justifies another runtime, a code change,
  code inspection, or stopping the micro-scheduler slice.

## Command(s)

```text
Spawned read-only sub-agent 019f1e45-ee1e-7283-8b27-712f2426e477
with this checkpoint:

Read goal.md, AGENTS.md, history/104, history/105, and history/106. Evaluate
the effective-state tick-block IRQ defer validation. Answer the standard
loop-check questions, include the required Progress-Method Critique, and
critique the proposed next step: inspect why cpu_tb_exec still returns
tb_exit=3 on the deferred 0x80030e84 TB after CPU_INTERRUPT_HARD and
exit_request are cleared.
```

## Inputs And Artifacts

- Latest runtime log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1/browser-runtime.log`
- Latest combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log`
- Latest run summary: `history/106-tick-block-irq-defer-effective-runtime.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `deferred_tb_exit3_source`, `first_deferred_tb_expected_path`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: critique decision was `revise`.
- The checkpoint said this is not looping as a process because
  `irq_defer_engaged` moved from skipped to yes.
- It said another ready-edge IRQ-defer runtime variant would be looping because
  the causal field did not move: `browser_first_watch_read_ticks` stayed `0`
  and post-service edge preservation stayed worse than baseline.
- Narrowest next fact: why the deferred `0x80030e84` TB still returns
  `tb_exit=3` with next PC unchanged after `CPU_INTERRUPT_HARD` and
  `exit_request` are supposedly cleared.
- It killed the hypothesis that one-TB IRQ defer is sufficient once it engages.
- It kept the hypothesis that browser reaches the watched read too early
  relative to PIT/PIC/CPU execution ordering.
- It revised the micro-scheduler hypothesis toward identifying why the TB
  cannot execute normally even with hard IRQ masked.

## Decision

- Status: current.
- Why: the next action should be read-only code inspection, not another runtime
  or behavioral patch.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: inspect `cpu_tb_exec` and TB exit handling around
  `TB_EXIT_REQUESTED`, `exit_request`, icount, and interrupt checks. Do not run
  again unless inspection identifies a specific field-changing candidate.

## Progress-Method Critique

- The critique said the metrics still connect to the real goal because strict
  browser `dashboard=xbe-executed` remains the gate before visible main-menu
  proof and game launch.
- It warned the work is close to becoming too diagnostic-heavy if it stays on
  IRQ-defer variants.
- It said the history/loop-check process is helping by preventing another
  runtime retry and forcing the next question back to one causal field.
- It recommended code inspection, not runtime probing and not a new behavioral
  patch yet.
- Process adjustment for the next 2-3 turns: require the next action to either
  explain `tb_exit=3` at the deferred TB or abandon the IRQ-defer
  micro-scheduler slice.

## Next Step

- Narrow follow-up: inspect the TCG TB execution path to classify
  `deferred_tb_exit3_source` before making more code changes.
