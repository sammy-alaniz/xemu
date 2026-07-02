# 227. Pre-TB Scheduler Quarantine Loop Check

## Purpose

Run the required bounded loop check after the shape-regressed runtime in
`history/226-pre-tb-scheduler-runtime-shape-regressed.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/223-pre-tb-scheduler-runtime-loop-check.md`
- `history/225-pre-tb-scheduler-runtime-escalation-loop-check.md`
- `history/226-pre-tb-scheduler-runtime-shape-regressed.md`

## Loop-Guard Fields

- `pre_tb_scheduler_branch_quarantined`
- `browser_first_watch_read_ticks`

## Findings

The sub-agent decision was `revise`.

The checkpoint found that the preservation guard failed, so
`browser_first_watch_read_ticks` is not interpretable from the pre-TB
scheduler runtime. It explicitly rejected another runtime or parameter tweak.

Allowed next action:

- quarantine or revert the pre-TB routing;
- keep the before-interrupt hook quarantined;
- build only after cleanup;
- do not rerun this scheduler mode after quarantine;
- return future target selection to the stable ready-edge host4 CPU-flow
  baseline.

Progress-method critique: this branch has crossed into the failed diagnostic
pattern. It was behavior-moving in intent, but the single preservation-gated
runtime regressed before B4/dashboard read. Quarantining it now keeps the work
aligned with strict browser dashboard execution, visible main menu proof, and
eventual game load.

## Decision

Revise.

## Next Step

Disable the pre-TB scheduler owner route and build only. Do not run another
pre-TB scheduler runtime.
