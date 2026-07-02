# PIT Bridge Plumbing Build Static Pass

## Purpose

- One new fact this run was supposed to produce: `pit_bridge_activation_plumbing_build_status`.

## Command(s)

```sh
sed -n '1,120p' scripts/xbox-browser-runtime-firefox-bidi.mjs
sed -n '300,360p' scripts/xbox-browser-runtime-smoke.sh
sed -n '630,708p' scripts/xbox-browser-runtime-smoke.sh
sed -n '520,585p' browser/xbox-boot/main.js
sed -n '260,325p' browser/xbox-boot/worker.js

git diff --check -- scripts/xbox-browser-runtime-smoke.sh scripts/xbox-browser-runtime-firefox-bidi.mjs browser/xbox-boot/main.js browser/xbox-boot/worker.js
bash -n scripts/xbox-browser-runtime-smoke.sh
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
node --check browser/xbox-boot/main.js
node --check browser/xbox-boot/worker.js
rg -n "browserBootPitPreStreamBridge|browser_boot_pit_pre_stream_bridge|XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE" scripts/xbox-browser-runtime-smoke.sh scripts/xbox-browser-runtime-firefox-bidi.mjs browser/xbox-boot/main.js browser/xbox-boot/worker.js ui/xemu-headless.c
```

## Inputs And Artifacts

- Patched files:
  - `scripts/xbox-browser-runtime-smoke.sh`
  - `scripts/xbox-browser-runtime-firefox-bidi.mjs`
  - `browser/xbox-boot/main.js`
  - `browser/xbox-boot/worker.js`
- Existing C-side consumer:
  - `ui/xemu-headless.c`
- Output directory/log: terminal static-check output only
- Fixture assumptions: no browser runtime was run; no WASM rebuild was needed because only browser/shell plumbing changed.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pit_bridge_activation_plumbing_build_status`

## Findings

- Result: `pit_bridge_activation_plumbing_build_status=pass`.
- Added smoke-script option docs for:
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE`
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT`
- Added both settings to the Playwright-generated `traceOptions` object.
- Added both settings to the final environment handoff used by the Firefox BiDi runtime script.
- Added both settings to Firefox BiDi `traceOptions` and summary output.
- Added browser UI trace option specs:
  - `browserBootPitPreStreamBridge` / `xemuBrowserBootPitPreStreamBridge` / `browser_boot_pit_pre_stream_bridge`
  - `browserBootPitPreStreamBridgeLimit` / `xemuBrowserBootPitPreStreamBridgeLimit` / `browser_boot_pit_pre_stream_bridge_limit`
- Added worker fixture-writer specs:
  - `browser_boot_pit_pre_stream_bridge.txt`
  - `browser_boot_pit_pre_stream_bridge_limit.txt`
- Static verification passed:
  - `git diff --check` clean,
  - `bash -n scripts/xbox-browser-runtime-smoke.sh` passed,
  - `node --check scripts/xbox-browser-runtime-firefox-bidi.mjs` passed,
  - `node --check browser/xbox-boot/main.js` passed,
  - `node --check browser/xbox-boot/worker.js` passed.
- `rg` confirms the new keys now appear in smoke script, Firefox BiDi script, browser main, worker fixture writer, and C-side consumer.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the activation plumbing is now statically wired. Runtime behavior remains untested after plumbing and still requires a separate loop check before any run.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/243-pit-bridge-plumbing-patch-loop-check.md` approved only env/traceOptions/fixture plumbing plus build/static verification, with no runtime.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique. If approved, at most one properly plumbed browser runtime may be run; if it activates and regresses preservation or fails to move the primary field, quarantine without limit tuning.
