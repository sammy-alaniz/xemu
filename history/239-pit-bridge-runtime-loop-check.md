# PIT Bridge Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether the built PIT-attributed pre-stream bridge may be tested in exactly one browser runtime.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest build summary: `history/238-pit-attributed-prestream-bridge-build.md`
- Output directory/log: sub-agent response only
- Fixture assumptions: patch is opt-in, default bridge limit is 1, build already passed, and no runtime has been run with the new bridge.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether a single bridge runtime is approved, and the single field it may change.

## Findings

- Result: continue.
- The sub-agent accepted `pit_attributed_pre_stream_bridge_build_status=pass` as in-scope:
  - opt-in only,
  - PIT-attributed timers only,
  - default limit 1,
  - no all-timer pump,
  - no scheduler revival,
  - no strict B6 weakening.
- Exactly one runtime is approved.
- One field for that runtime: `pit_attributed_pre_stream_bridge_preserves_post_service_edge`.
- Secondary tick observation is allowed only if preservation passes.
- Required preservation gates before interpreting tick movement:
  - browser runtime evidence,
  - display capture,
  - dashboard read/load/entry-ready,
  - section-map,
  - PFIFO stream-idle,
  - vector `0x30` service/IRET,
  - strict B6 unchanged,
  - `0x80030e84->0x80030f31` post-service edge,
  - bridge activation marker `main-loop=timers source=browser-pit-prestream-bridge`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: one behavior validation is allowed because it tests the narrow bridge against the exact native/browser timer-service gap.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: this is not yet a diagnostic loop, but the method risk is repeating earlier timer delivery under a narrower name. Branch-exit rule: if preservation gates regress or if preservation passes without first-read tick improvement, quarantine/disable the bridge and return to stable-baseline selection. No limit tuning and no second bridge runtime.

## Next Step

- Narrow follow-up: run exactly one browser runtime with the PIT bridge enabled and existing preservation checks, then write history before any further action.
