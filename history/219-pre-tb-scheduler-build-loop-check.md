# 219. Pre-TB Scheduler Build Loop Check

## Purpose

Run the required bounded loop check after
`history/218-pre-tb-scheduler-owner-patch.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/217-pre-tb-behavior-first-loop-check.md`
- `history/218-pre-tb-scheduler-owner-patch.md`

## Loop-Guard Fields

- `pre_tb_scheduler_owner_build_status`
- `browser_first_watch_read_ticks`

## Findings

The sub-agent decision was `continue`.

It found that the patch stayed within the approved scope:

- the opt-in pre-first-read scheduler routes through the pre-TB pump path;
- the before-interrupt hook remains quarantined;
- owner labeling is `tcg-pre-tb`;
- PFIFO stream-idle is required before arming;
- no broad gate markers were added;
- exact-PC IRQ defer was not revived;
- no interrupt, exit-request, or icount state is manually mutated;
- no broadening to the rejected pre-stream `0x80014f3d` path occurred.

The checkpoint also clarified that the next action can only change
`pre_tb_scheduler_owner_build_status`. It cannot prove
`browser_first_watch_read_ticks`; that requires a later preservation-gated
runtime.

Progress-method critique: building this patch remains on the path toward
strict browser dashboard execution, main menu, and game load because it is a
behavior-moving prerequisite for the primary metric. The checkpoint explicitly
said the next step should be build-only, followed by another loop check before
any runtime.

## Decision

Continue.

## Next Step

Run the Podman WASM build and record the result before any runtime.
