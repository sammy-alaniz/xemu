# 228. Pre-TB Scheduler Quarantine Patch

## Purpose

Quarantine the pre-TB scheduler routing after the shape-regressed runtime in
`history/226-pre-tb-scheduler-runtime-shape-regressed.md` and the loop-check
decision in `history/227-pre-tb-scheduler-quarantine-loop-check.md`.

The one field this code change can change is
`pre_tb_scheduler_branch_quarantined`.

## Command

Manual patch with `apply_patch`.

## Inputs and Artifacts

- Source file changed: `xemu-xbe.c`
- Shape-regressed runtime:
  `build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log`
- Loop-check decision:
  `history/227-pre-tb-scheduler-quarantine-loop-check.md`

## Loop-Guard Fields

- `pre_tb_scheduler_branch_quarantined`

## Findings

The patch disables the pre-TB scheduler owner route by restoring
`xemu_xbe_boot_trace_tcg_timer_pump_before_tb()` to the older
`pit-before-pfifo-transition-activity-pre-tb-defer` mode only.

It also restores the pre-first-read scheduler comment and owner labels to the
historical `tcg-pre-interrupt` wording and removes the added stream-idle
arming requirement from the scheduler site-ready predicate.

The before-interrupt hook itself remains quarantined because
`xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` still returns `false`.

## Decision

`pre_tb_scheduler_branch_quarantined=patched-not-built`

## Next Step

Run the required loop check before the build-only verification.
