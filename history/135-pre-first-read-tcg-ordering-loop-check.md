# 135. Pre-first-read TCG ordering loop check

## Purpose

Run the required bounded loop check after the same-origin runtime restored the B6 boundary but failed to improve the first shared-word read tick value.

## Loop-Guard Field

- `tcg_pump_after_first_read_reason`

## Exact Command

Sub-agent loop check sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/134-pre-first-read-tcg-v2-same-origin-runtime.md`
- Same-origin runtime:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log`
- Same-origin combined runtime:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log`

## Findings

The sub-agent reported:

- This is not looping if the next step is a static ordering audit.
- Another browser runtime or another readiness tweak would be looping before understanding why the new `tcg=timer-pump` marker fires too late.
- The narrow next fact is `tcg_pump_after_first_read_reason`.
- Kill the hypothesis that allowing `pc=0x80030e84` is sufficient to improve the pre-service first-read tick metric.
- Keep the same-origin port `8846` harness path for this slice.
- Revise the problem from a closed PC predicate to pump ordering relative to memory-watch read and wait-snapshot state.
- The current `pcrtc vblank-suppress` wait snapshot may also be invalidating edge-decision even though PFIFO idle was already observed.
- The proposed no-emulation audit is justified and should cover the TCG call site, memory-watch observation order, tick-block/edge-decision order, and wait-snapshot source change around the same-origin boundary.

## Progress-Method Critique

The sub-agent reported:

- The work is still connected to Xbox main menu and game launch because strict browser B6 remains the required gate.
- The work is diagnostic-heavy, but the last run was productive because it restored the boundary and proved the new mode fires.
- The history/loop-check process is helping for the next 2-3 turns by preventing another runtime before understanding the ordering failure.
- Process adjustment: the next code change, if any, must name the exact ordering point it moves before the first watched read and the exact wait-snapshot gate it preserves or replaces.

## Decision

`continue`

## Next Step

Do a static ordering audit of the TCG pump call site, first shared-word observation, tick-block/edge-decision order, and wait-snapshot source change. Do not run another browser runtime until that audit identifies the exact ordering field to change.
