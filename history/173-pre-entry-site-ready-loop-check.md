# 173. Pre-Entry Site-Ready Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after
`history/172-pre-entry-site-ready-inspection.md` before making any code change.

## Inputs / Artifacts

- `history/172-pre-entry-site-ready-inspection.md`
- Current proposed patch:
  add a cheap early guard in
  `xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready()` so the
  diagnostic scheduler predicate returns before clock/context/serviceability
  work unless the opt-in mode is selected, boot trace is enabled, dashboard
  entry-ready is true, and the interval is usable.

## Loop-Guard Field

- `pre_entry_site_ready_side_effect_reduced`
- Secondary: `post_sti_build_early_timeout_cause`

## Findings

The sub-agent decision was `continue`.

The checkpoint judged the proposed patch to be a narrow revision rather than a
repeat runtime loop because the repeated failure happens before dashboard
read/load, and the inspection identified a specific pre-entry code-shape risk.

The checkpoint also judged that the patch preserves the B6 contract because it
does not touch the strict `dashboard=xbe-executed` marker, does not weaken the
checker, and does not broaden the exact `0x80014f32` scheduler target.

## Progress-Method Critique

The current method is still connected to B6 through the first-read tick-gap
boundary, but this branch is at risk of becoming perturbation-driven. The next
steps must stay strict:

- remove pre-entry side effects
- build only
- write history
- run another loop check before any runtime retry

If a later runtime still times out before dashboard read/load, quarantine or
rollback of the micro-scheduler branch should be considered before further
tuning.

## Decision

Continue with the narrow guard patch.

## Next Step

Patch `xemu-xbe.c` only, then run a build check. Do not run a browser runtime in
the same step.
