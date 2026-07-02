# PIT Bridge Plumbing Patch Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether the static plumbing finding justifies a code patch or requires quarantining the PIT bridge branch.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Static plumbing summary: `history/242-pit-bridge-activation-plumbing-static.md`
- Runtime summary: `history/240-pit-bridge-runtime-not-activated.md`
- Runtime log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log`
- Output directory/log: sub-agent response only
- Fixture assumptions: the previous runtime did not prove bridge behavior because the new setting did not reach WASM.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether a plumbing patch is approved, and the one field it may change.

## Findings

- Result: continue.
- The sub-agent agreed `pit_bridge_activation_plumbing_status=not-plumbed` is non-redundant and consistent with loop-control.
- The sub-agent said quarantining the bridge now would be premature because the approved runtime did not actually test bridge behavior.
- One plumbing-only code patch is approved.
- Scope:
  - add `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE` to the browser runtime trace option path,
  - add `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT` to the browser runtime trace option path,
  - add matching fixture writer entries for `browser_boot_pit_pre_stream_bridge.txt` and `browser_boot_pit_pre_stream_bridge_limit.txt`.
- Exactly one next field: `pit_bridge_activation_plumbing_build_status`.
- No runtime is approved until after build/history/loop-check.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run in this checkpoint.

## Decision

- Status: current
- Why: this is setup correction only, not behavior tuning.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: method risk remains timer-bridge looping. The constraint is patch only env/traceOptions/fixture plumbing and run build/static verification. Later, after one properly activated runtime, if preservation regresses or the primary field does not move, quarantine without limit tuning.

## Next Step

- Narrow follow-up: patch only the browser runtime plumbing for the two PIT bridge settings and verify build/static status; no runtime.
