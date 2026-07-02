# 177. Pre-Entry Site-Ready Early Timeout Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after the controlled runtime retry
again timed out before dashboard read/load.

## Inputs / Artifacts

- `history/176-pre-entry-site-ready-guard-runtime-early-timeout.md`
- Runtime log:
  `build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log`

## Loop-Guard Field

- `micro_scheduler_branch_quarantined_restores_dashboard_read_load`

## Findings

The sub-agent decision was `revise`.

The retry reproduced the same early timeout before dashboard read/load, so the
exact post-STI scheduler field remains untested. The checkpoint judged that a
further static inspection is unlikely to change the decision because the
pre-entry guard was already the narrowest plausible side-effect reduction.

Recommended quarantine order:

1. Disable the before-interrupt hook for the micro-scheduler mode, because it is
   the highest-risk structural change touching the CPU loop before the known-good
   boundary.
2. If that is not enough or the diff is cleaner, quarantine the whole
   `pit-pre-first-read-micro-scheduler` mode path so selecting it cannot alter
   execution before entry-ready.
3. Do not preserve/tune exact post-STI serviceability or gate marker behavior
   until dashboard read/load is restored.

## Progress-Method Critique

The branch has crossed into perturbation-driven diagnostics. Multiple runtime
attempts now fail before dashboard read/load, so the branch is no longer
measuring the first-read tick gap. Boundary preservation must become a hard
precondition before more scheduler experiments.

## Decision

Revise by quarantining the before-interrupt micro-scheduler hook first.

## Next Step

Patch the micro-scheduler before-interrupt path so it cannot perturb early CPU
loop execution, then build before any restoration runtime.
