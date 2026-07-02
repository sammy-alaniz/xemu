# PIT Bridge Plumbing Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether the failed PIT bridge runtime should be quarantined or whether one static plumbing inspection is justified.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Runtime summary: `history/240-pit-bridge-runtime-not-activated.md`
- Runtime log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log`
- Combined browser log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response only
- Fixture assumptions: runtime env included `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE=1` and limit `1`, but no fixture-file plumbing was added for those new settings.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether a static plumbing inspection is allowed, and the single field it may explain.

## Findings

- Result: continue.
- The sub-agent said the runtime branch-exit rule is triggered for runtime interpretation:
  - preservation failed,
  - bridge did not activate,
  - tick movement is not interpretable.
- The sub-agent did not approve another runtime or limit tuning.
- The sub-agent did not require immediate quarantine because the activation marker was absent despite environment variables being set.
- One static inspection is justified as setup verification, not as a second bridge experiment.
- Exactly one next field: `pit_bridge_activation_plumbing_status`.
- Scope of the inspection: determine whether `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE` and its limit reach `ui/xemu-headless.c` in browser runtime, including env propagation versus fixture-file plumbing.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run in this checkpoint.

## Decision

- Status: current
- Why: the next action is limited to static plumbing inspection. If the bridge was enabled and still did not activate, quarantine it. If it was not enabled due to plumbing, fix only the enable path/build, then run another loop check before any runtime.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the method risk is looping on timer bridges. The only allowed continuation is one static setup/plumbing check because the run may not have tested the bridge at all.

## Next Step

- Narrow follow-up: static inspection only for `pit_bridge_activation_plumbing_status`; no runtime and no behavior tuning.
