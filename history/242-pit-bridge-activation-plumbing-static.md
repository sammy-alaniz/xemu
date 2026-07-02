# PIT Bridge Activation Plumbing Static

## Purpose

- One new fact this run was supposed to produce: `pit_bridge_activation_plumbing_status`.

## Command(s)

```sh
rg -n "browser_boot_deterministic|browser_headless_timer_pump|xbe_.*txt|fixtures|xemu-fixtures|XEMU_BROWSER_BOOT|XEMU_BOOT_TRACE_XBE|call_chain_trace|deterministic" scripts tests build-aux ui src . --glob '!build-real-b3-matrix/**' --glob '!build-wasm-pic/**' --glob '!subprojects/**'
sed -n '1,240p' scripts/xbox-browser-runtime-smoke.sh
sed -n '240,520p' scripts/xbox-browser-runtime-smoke.sh
rg -n "traceOptions|BROWSER_DIAGNOSTIC_APPLY|browserBootDeterministic|browserHeadlessTimerPump|xbeTimerOpportunity|callChainTrace|xemu-fixtures|writeFile|mount|FS.writeFile|diagnostic" scripts/xbox-browser-runtime-smoke.sh browser tests ui --glob '!build-real-b3-matrix/**'
sed -n '520,760p' scripts/xbox-browser-runtime-smoke.sh
rg -n "browser_headless_timer_pump_progress_limit|browser_boot_deterministic|xbe_timer_opportunity_limit|call_chain_trace|BROWSER_DIAGNOSTIC_APPLY|diagnostic" browser scripts ui --glob '!build-real-b3-matrix/**'
sed -n '250,375p' browser/xbox-boot/worker.js
sed -n '515,620p' browser/xbox-boot/main.js
sed -n '500,590p' scripts/xbox-browser-runtime-firefox-bidi.mjs
rg -n "pit_pre_stream|PIT_PRE_STREAM|browser_boot_pit_pre_stream|browserPit|pitPre" scripts/xbox-browser-runtime-smoke.sh browser/xbox-boot/worker.js browser/xbox-boot/main.js scripts/xbox-browser-runtime-firefox-bidi.mjs ui/xemu-headless.c history/240-pit-bridge-runtime-not-activated.md
rg -n "BROWSER_DIAGNOSTIC_APPLY name=browser_pit|browser_boot_pit|pit-prestream|browser-pit-prestream-bridge" build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
sed -n '760,845p' scripts/xbox-browser-runtime-smoke.sh
```

## Inputs And Artifacts

- Runtime log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log`
- Browser runtime harness: `scripts/xbox-browser-runtime-smoke.sh`
- Browser page trace UI/options: `browser/xbox-boot/main.js`
- Browser worker fixture writer: `browser/xbox-boot/worker.js`
- Firefox BiDi runtime reporter: `scripts/xbox-browser-runtime-firefox-bidi.mjs`
- Fixture assumptions: C code reads `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE` via `getenv()` or `browser_boot_pit_pre_stream_bridge.txt`; the browser runtime normally uses `/xemu-fixtures/*.txt` because host shell env vars are not automatically visible inside the WASM process.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pit_bridge_activation_plumbing_status`

## Findings

- Result: `pit_bridge_activation_plumbing_status=not-plumbed`.
- The smoke script constructs a fixed `traceOptions` object from known environment variables. It includes existing deterministic/headless timer fields, but not:
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE`
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT`
- The smoke script passes only that fixed `traceOptions` object into the page through `globalThis.xemuBrowserBootTraceOptions`.
- The smoke script's final environment handoff to the Node runtime also omits both new variables.
- `browser/xbox-boot/main.js` has a fixed `traceOptionSpecs` list for page/global trace options. It includes deterministic/headless timer fields, but not the new PIT bridge fields.
- `browser/xbox-boot/worker.js` has the fixed `traceOptionSpecs` list that writes `/xemu-fixtures/*.txt`. It includes:
  - `browser_boot_deterministic.txt`,
  - `browser_boot_deterministic_timer_steps.txt`,
  - `browser_boot_deterministic_warmup_progress_limit.txt`,
  - `browser_headless_timer_pump_progress_limit.txt`,
  - `browser_headless_timer_pump_mode.txt`,
  but not:
  - `browser_boot_pit_pre_stream_bridge.txt`,
  - `browser_boot_pit_pre_stream_bridge_limit.txt`.
- The runtime log has no `BROWSER_DIAGNOSTIC_APPLY name=browser_boot_pit...` line and no `main-loop=timers source=browser-pit-prestream-bridge` line.
- Therefore the previous runtime did not test the bridge behavior. It tested the baseline without the new bridge setting reaching WASM.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was static plumbing inspection.

## Decision

- Status: current
- Why: the activation failure is explained as setup/plumbing, not as a behavioral bridge failure. The bridge branch should not be runtime-tuned, but one fixture-plumbing patch is technically justified if approved by the next loop check.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/241-pit-bridge-plumbing-loop-check.md` approved one static setup/plumbing inspection only; it said to quarantine if the bridge was enabled and still did not activate, or fix only the enable path/build if it was not enabled due to plumbing.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique. If approved, patch only the browser runtime plumbing for the two new bridge settings and run build/static verification; do not run another browser runtime without a later loop check.
