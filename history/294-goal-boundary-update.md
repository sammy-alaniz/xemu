# 294 - Goal Boundary Update

## Purpose

- One new fact this change was supposed to produce:
  make the latest stable B6 boundary explicit in `goal.md` so future work is
  gated by the missing pre-stream serviceable state instead of another broad
  runtime probe.

## Command(s)

```sh
# Edited goal.md with apply_patch.
git diff --check -- goal.md
git diff -- goal.md
rg -n "deferred NV2A|native_pre_stream_serviceable_state_browser_mapping|browser_pre_stream_vector_service_state|pcrtc/intr-clear|Current process adjustment" goal.md
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Input histories:
  - `history/292-native-serviceable-state-browser-mapping.md`
  - `history/293-native-serviceable-state-loop-check.md`
- Updated file: `goal.md`
- Fixture assumptions: none.

## Expected Field(s)

- Loop-guard field(s) this change could change or explain:
  `current_b6_boundary_recorded`

## Findings

- Result:
  `goal.md` now records the stable boundary
  `native_pre_stream_serviceable_state_browser_mapping=no-equivalent-browser-state-before-stream-idle`.
- Important marker/comparator lines:
  - The deferred NV2A `DMA_PUT` observer branch is documented as
    runtime-negative and default-off diagnostic-only.
  - The current blocker now states that native services vector `0x30` before
    PFIFO stream-idle while waiting on `pcrtc/intr-clear`, but browser has no
    equivalent pre-stream vector service state and first reads `0x0003a890` at
    0 ticks.
  - M1 now requires designing an emulated-state-owned way to reach or replace
    that missing state before driving another deterministic runtime branch.
  - The loop-guard field list now includes
    `native_pre_stream_serviceable_state_browser_mapping` and
    `browser_pre_stream_vector_service_state`.
  - `git diff --check -- goal.md` passed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was documentation/process state only.

## Decision

- Status: current
- Why:
  This records the loop-check-approved boundary and blocks stale runtime modes
  until the next design names how it changes or explains the missing
  `pcrtc/intr-clear` serviceable state.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  The previous loop check approved updating `goal.md` and explicitly warned
  against old pump/vblank/PIT/scheduler/precommit and regressed DMA_PUT runtime
  branches.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  Keep metrics tied to strict dashboard execution and main-menu/game-launch
  proof; avoid generating more logs before a deterministic design exists.
- If yes, process adjustment for next 2-3 turns:
  Continue with design/code inspection only, centered on
  `browser_pre_stream_vector_service_state`, unless a loop check revises this.

## Next Step

- Narrow follow-up:
  Run the required bounded loop check before any next experiment, run, probe, or
  code change.
