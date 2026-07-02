# PIT Bridge Quarantine Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide the next mode after the plumbed PIT bridge runtime regressed preservation.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest runtime summary: `history/246-pit-bridge-plumbed-runtime.md`
- Runtime log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log`
- Boundary reducer output: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/b6-current-boundary.txt`
- Fixture assumptions: no new runtime or code change occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `pit_bridge_branch_quarantine_decision`
  - `next_mode_after_pit_bridge_regression`

## Findings

- Result: revise.
- The sub-agent found the PIT bridge branch is now at risk of looping.
- The branch-exit rule applies exactly:
  - activation occurred,
  - strict B6 stayed at `missing-xbe-executed-marker`,
  - the post-service edge regressed from `0x80030e84->0x80030f31` to `0x80030e4c->0x80030f45`,
  - edge-decision classification became `watch-write-without-focused-read`.
- The sub-agent said no PIT bridge limit tuning or second bridge runtime is justified.
- The narrowest next field is `pit_bridge_branch_quarantined_build_status`.
- Recommended next mode: code cleanup/quarantine.
- The sub-agent explicitly rejected immediate runtime probing, deterministic scheduler design, and `nv-user-dma-put` ordering as the next mode.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: the next action should remove or disable the experimental PIT bridge path enough that it cannot become the next runtime loop, while preserving the stable ready-edge host4 baseline.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: quarantine the PIT bridge branch now; do not tune it or rerun it.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still connects to strict dashboard execution because it refuses partial tick movement, but it is too close to timer-placement diagnostics; the history/loop-check process helped enforce a branch exit.
- If yes, process adjustment for next 2-3 turns: after quarantine, require one static stable-baseline field selection before any new code or runtime.

## Next Step

- Narrow follow-up: quarantine the PIT pre-stream bridge code/plumbing and run build/static checks only. Do not run another browser runtime.
