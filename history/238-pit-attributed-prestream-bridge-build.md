# PIT Attributed Prestream Bridge Build

## Purpose

- One new fact this run was supposed to produce: `pit_attributed_pre_stream_bridge_build_status`.

## Command(s)

```sh
git diff -- ui/xemu-headless.c xemu-xbe.c
git diff --check -- ui/xemu-headless.c xemu-xbe.c
nl -ba ui/xemu-headless.c | sed -n '300,430p'
nl -ba ui/xemu-headless.c | sed -n '713,930p'
nl -ba xemu-xbe.c | sed -n '1018,1032p'
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: build output from `scripts/docker-build-xemu-wasm.sh`
- Build artifact: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: runtime remains disabled until a later loop check; the new bridge is opt-in through `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE` or `browser_boot_pit_pre_stream_bridge.txt`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pit_attributed_pre_stream_bridge_build_status`

## Findings

- Result: `pit_attributed_pre_stream_bridge_build_status=pass`.
- `git diff --check -- ui/xemu-headless.c xemu-xbe.c` produced no whitespace errors.
- Added opt-in setting:
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE`
  - fixture file `browser_boot_pit_pre_stream_bridge.txt`
- Added tiny bounded bridge limit:
  - `XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT`
  - fixture file `browser_boot_pit_pre_stream_bridge_limit.txt`
  - default limit `1`
- The bridge activates only when the normal browser timer pump gate is closed, dashboard entry polling is active, virtual timers exist and are expired, and the bridge limit has not been consumed.
- The bridge source tag is `browser-pit-prestream-bridge`.
- The bridge runs only:
  `qemu_clock_run_timers_with_attrs_limit(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_XEMU_TCG_PUMP, QEMU_TIMER_ATTR_XEMU_TCG_PUMP, 1)`.
- The normal ready-edge, deterministic warmup, and bounded host-pump paths remain present and unchanged unless the new opt-in is enabled.
- `xemu_xbe_main_loop_timer_source_is_browser_diagnostic()` now accepts `browser-pit-prestream-bridge`, so a future runtime can report `main-loop=timers source=browser-pit-prestream-bridge` without relaxing the ordinary PFIFO readiness gate.
- Build output:
  - compiled `ui_xemu-headless.c.o`
  - compiled `xemu-xbe.c.o`
  - linked `qemu-system-i386.js`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the opt-in PIT-only bridge builds. Runtime behavior remains unproven and must be preservation-gated before promotion.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/237-pit-attributed-bridge-loop-check.md` approved exactly one small code patch plus build-only verification, with no runtime until another loop check.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique. If approved, run one browser runtime using the new opt-in bridge and the existing preservation gates; branch-exit immediately if B4/B5/read/load/entry-ready/section-map/stream-idle/vector `0x30`/IRET/post-service edge regresses.
