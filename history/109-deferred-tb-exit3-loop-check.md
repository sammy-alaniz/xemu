# Deferred TB Exit3 Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the static
  `deferred_tb_exit3_source` diagnosis in `history/108` justifies a bounded
  code change and one validation run.

## Command(s)

```text
Spawned read-only sub-agent 019f1e48-bcbf-76f3-85c3-986d9772e834
with this checkpoint:

Read goal.md, AGENTS.md, history/106, history/107, and history/108. Evaluate
the static diagnosis that the deferred TB still exits with tb_exit=3 because
the generated TB start sees cpu->neg.icount_decr.u16.high == -1. Answer the
standard loop-check questions, include the required Progress-Method Critique,
and critique a tiny opt-in patch that saves, clears, and restores that high
half around the one-TB defer.
```

## Inputs And Artifacts

- Static inspection summary:
  `history/108-deferred-tb-exit3-static-inspection.md`
- Latest runtime summary:
  `history/106-tick-block-irq-defer-effective-runtime.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `first_deferred_tb_expected_path`, `tick_block_completion_before_edge_decision`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said `history/108` changed the boundary to a plausible
  `deferred_tb_exit3_source`: generated TB start still sees
  `neg.icount_decr.u16.high == -1` and exits through `TB_EXIT_REQUESTED`.
- Narrowest next fact: whether clearing/restoring
  `cpu->neg.icount_decr.u16.high` makes the first deferred TB stop returning
  `tb_exit=3` and sets `first_deferred_tb_expected_path=yes`.
- It killed the hypothesis that clearing HARD IRQ and `exit_request` is enough
  for the one-TB defer.
- It kept the hypothesis that browser still reaches the watched read before
  timer/tick catch-up.
- It revised the one-TB defer to mask all three paths for one block:
  HARD IRQ, `exit_request`, and the TCG high-half exit-request latch.

## Decision

- Status: current.
- Why: the next action is justified as one opt-in code change plus exactly one
  validation.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: judge the next run first on whether `tb_exit=3`
  disappears and the deferred block executes. If that passes but ticks stay at
  0 or the post-service edge regresses, stop iterating on IRQ-defer variants.

## Progress-Method Critique

- The critique said the metrics still connect to the real goal because
  deterministic dashboard execution is the gate before visible main-menu proof
  and game launch.
- It said this step is diagnostic-heavy but not a rerun because it tests a newly
  explained failure mechanism from `history/108`.
- It said history and loop checks are helping by preventing another broad
  ready-edge run.
- It recommended code change plus exactly one runtime validation.
- Process adjustment for the next 2-3 turns: after that run, accept only three
  outcomes: promote if ticks move and edge is preserved; revise away from
  one-TB defer if expected path works but ticks do not move; stop this slice if
  `tb_exit=3` or edge regression persists.

## Next Step

- Narrow follow-up: patch the one-TB defer to save, clear, and restore
  `cpu->neg.icount_decr.u16.high`, log before/post/restored high-half values,
  build, and run exactly one validation.
