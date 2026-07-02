# 223. Pre-TB Scheduler Runtime Loop Check

## Purpose

Run the required bounded loop check after the build pass in
`history/222-pre-tb-scheduler-build-pass.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/218-pre-tb-scheduler-owner-patch.md`
- `history/219-pre-tb-scheduler-build-loop-check.md`
- `history/221-pre-tb-scheduler-build-escalation-loop-check.md`
- `history/222-pre-tb-scheduler-build-pass.md`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`

## Findings

The sub-agent decision was `continue`.

It approved exactly one preservation-gated browser runtime using the stable
ready-edge host4 shape plus the opt-in pre-TB scheduler mode.

The runtime may be interpreted only if these gates pass:

- browser runtime evidence;
- display capture;
- dashboard read/load/entry-ready;
- section-map;
- PFIFO stream-idle;
- vector `0x30` service/IRET;
- `0x80030e84->0x80030f31` post-service edge.

If those gates regress, classify the run as shape-regressed and do not treat
tick movement or scheduler markers as causal. If the gates pass but
`browser_first_watch_read_ticks` stays `0` or `1`, stop this scheduler branch
rather than tuning around it.

Progress-method critique: this remains a bounded behavior validation toward
strict browser dashboard execution, main menu, and game load. It is not
metric-tuning yet because there is one built code slice, one primary field,
and explicit preservation gates.

## Decision

Continue.

## Next Step

Run one browser runtime and then write the result to history before any
follow-up runtime or parameter tuning.
