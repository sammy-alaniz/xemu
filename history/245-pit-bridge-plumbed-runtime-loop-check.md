# PIT Bridge Plumbed Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether one properly plumbed PIT bridge browser runtime is approved.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Plumbing/static summary: `history/244-pit-bridge-plumbing-build-static-pass.md`
- Previous unplumbed runtime summary: `history/240-pit-bridge-runtime-not-activated.md`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response only
- Fixture assumptions: the PIT bridge settings are now statically wired through smoke script, browser page trace specs, worker fixture writer, and Firefox BiDi summary path.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether one properly plumbed runtime is allowed, and the single field it may change.

## Findings

- Result: continue.
- The sub-agent agreed the plumbing patch stayed in scope:
  - only the two PIT bridge options were wired,
  - static checks passed,
  - no runtime was run.
- Exactly one properly plumbed browser runtime is approved.
- One field for that runtime: `pit_attributed_pre_stream_bridge_preserves_post_service_edge`.
- Required activation evidence:
  - `BROWSER_DIAGNOSTIC_APPLY name=browser_boot_pit_pre_stream_bridge` or equivalent fixture application,
  - `main-loop=timers source=browser-pit-prestream-bridge`.
- Required preservation gates before interpreting tick movement:
  - browser runtime evidence,
  - display capture,
  - dashboard read/load/entry-ready,
  - section-map,
  - PFIFO stream-idle,
  - vector `0x30` service/IRET,
  - strict B6 unchanged,
  - `0x80030e84->0x80030f31` post-service edge.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run in this checkpoint.

## Decision

- Status: current
- Why: this is the only approved properly plumbed bridge runtime; the previous runtime did not activate the bridge.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: method risk is now close to a PIT-bridge loop. Branch-exit rule: if activation occurs and preservation regresses, or if preservation passes but first watched read does not improve, quarantine the bridge without limit tuning or another runtime.

## Next Step

- Narrow follow-up: run exactly one properly plumbed browser runtime with the PIT bridge enabled and existing preservation checks; write history before any further action.
