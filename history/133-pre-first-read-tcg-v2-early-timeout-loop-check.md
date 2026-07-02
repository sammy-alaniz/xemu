# 133. Pre-first-read TCG v2 early-timeout loop check

## Purpose

Run the required bounded loop check after the v1/v2 early-timeout comparison and before any new runtime experiment.

## Loop-Guard Field

- `same_origin_v2_reaches_b6_boundary`

## Exact Command

Sub-agent loop check sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/132-pre-first-read-tcg-v2-early-timeout-compare.md`
- Previous runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log`
- Rebuilt runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`

## Findings

The sub-agent reported:

- This is not looping if the next run is strictly a same-origin control.
- The narrow next fact is `same_origin_v2_reaches_b6_boundary`.
- Kill the hypothesis that the v2 early timeout is evidence against the `0x80030e84` predicate, because the predicate is unreachable before entry-ready.
- Keep port/origin setup drift as the leading explanation, because v1 on port `8846` had `BROWSER_ASSET_AUTO result=pass name=hdd`, while v2 on port `8847` did not.
- Revise the next validation as a controlled harness-restoration test, not yet a B6 scheduler test.
- A single same-origin controlled runtime is justified. It should restore only `XEMU_BROWSER_RUNTIME_PORT=8846`, keep the v2 command otherwise, write a new artifact directory, and judge first on `BROWSER_ASSET_AUTO` plus reaching the prior B6 boundary before interpreting any TCG result.

## Progress-Method Critique

The sub-agent reported:

- The work is still tied to Xbox main menu and game launch because strict browser B6 remains the gate before visible main-menu proof and game launch.
- The immediate work is harness recovery rather than dashboard progress, which is acceptable for one turn because the prior runtime stopped before the intended scheduler boundary.
- The history/loop-check process helped by preventing an early harness timeout from being misclassified as a failed TCG design.
- The process will slow progress if it allows more port/origin churn after this control.
- Process adjustment: change only the port/origin variable for the next run, write a new artifact, and declare that failure to reach `BROWSER_ASSET_AUTO` or dashboard-read means stopping runtime probing and inspecting harness persistence/build regression instead.

## Decision

`continue`

## Next Step

Run one controlled browser runtime using the rebuilt wasm with the known v1 origin/port `8846`, otherwise keeping the v2 command, and write to a new artifact directory.
