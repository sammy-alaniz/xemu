# 189. Stable Boundary Field Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after selecting
`first_kick_after_last_opportunity_source` as the next stable-baseline boundary
field.

## Inputs / Artifacts

- `history/188-stable-baseline-boundary-field-selection.md`
- Stable browser CPU-flow baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Field

- `first_kick_after_last_opportunity_source`

## Findings

The sub-agent decision was `continue`.

`first_kick_after_last_opportunity_source` is the right next field. This does
not repeat old PFIFO diagnostics because the existing PFIFO ordering facts are
already established; the missing piece is source provenance. The repository
notes explicitly name source-tagged `pfifo=scheduler` markers as the next
actionable boundary change.

Static/source inspection is justified before any code edit. Any edit should be
marker-only, non-perturbing, and limited to tagging existing PFIFO scheduler kick
call sites so the current classifier can distinguish the first kick source after
the timer-opportunity window without changing scheduling behavior.

## Progress-Method Critique

The selected field stays on the strict B6 path because it targets the known
pre-service tick gap: browser timer opportunities exist before PFIFO window
publication, but PFIFO production/kick ordering still lacks provenance.

For the next 2-3 turns, constrain work to:

- source inspection
- one bounded marker-only patch/build if call sites are clear
- one runtime only if the marker can change
  `first_kick_after_last_opportunity_source`

Do not run broad PFIFO probes, timer-pump tuning, scheduler reruns, or the
quarantined before-interrupt path.

## Decision

Continue with source inspection for PFIFO scheduler kick source tags.

## Next Step

Inspect PFIFO scheduler marker and kick call sites to identify the smallest
non-perturbing marker-only patch.
