# 218. Pre-TB Scheduler Owner Patch

## Purpose

Apply the small behavior-first code slice approved by
`history/217-pre-tb-behavior-first-loop-check.md`.

The one field this code change can change is
`pre_first_read_scheduler_owner`, which is a prerequisite for later measuring
`browser_first_watch_read_ticks`.

## Command

Manual patch with `apply_patch`.

## Inputs and Artifacts

- Source file changed: `xemu-xbe.c`
- Prior checkpoint:
  `history/217-pre-tb-behavior-first-loop-check.md`

## Loop-Guard Fields

- `pre_first_read_scheduler_owner`
- `browser_first_watch_read_ticks`

## Findings

The patch makes the opt-in pre-first-read scheduler use the pre-TB pump path
instead of relying on the quarantined before-interrupt hook:

- `xemu_xbe_boot_trace_tcg_timer_pump_before_tb()` now returns true for the
  pre-first-read scheduler site-ready predicate.
- `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` remains quarantined.
- The serviceability comment now describes pre-TB ownership rather than
  before-interrupt ownership.
- The scheduler owner labels emitted in start/timer-pump markers now say
  `tcg-pre-tb`.
- The site-ready predicate now requires PFIFO stream-idle transition before
  arming, avoiding the earlier rejected pre-stream path.

No broad gate marker path was added. No exact-PC IRQ defer path was enabled.
No interrupt, exit-request, or icount state is manually mutated.

## Decision

Patch applied. Not yet built.

## Next Step

Run the required loop check before any build or source probe.
