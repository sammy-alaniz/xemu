# Edge Decision Runtime Early Timeout

## Purpose

- One new fact this run was supposed to produce: whether `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` populates pre/post `0x80030e84` decision markers in the deterministic browser runtime, and whether that explains or improves `browser_post_service_top_edge`.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin NODE_PATH= \
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_BROWSER_RUNTIME_MODE=real \
XEMU_BROWSER_RUNTIME_EXPECT_B3=1 \
XEMU_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_BROWSER_RUNTIME_BROWSER=firefox \
XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic \
XEMU_BROWSER_RUNTIME_PORT=8834 \
XEMU_BROWSER_RUNTIME_BOOT_MS=90000 \
XEMU_BROWSER_RUNTIME_TIMEOUT_MS=150000 \
XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT=1 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8 \
XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BROWSER_BOOT_DETERMINISTIC=1 \
XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log \
  2>&1

rg -n "edge-decision" build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
rg -n "BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_EVIDENCE|DISPLAY_CAPTURE_EVIDENCE|DASHBOARD_SECTION_MAP_EVIDENCE|DASHBOARD_LOADED_EVIDENCE|missing-xbe-executed-marker|dashboard=xbe-executed" build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
rg -n "BOOT_MARK b6 dashboard=kernel-loop-probe .*0x80030e84|BOOT_MARK b6 memory-watch|BOOT_MARK b6 main-loop=timers|BOOT_MARK b6 pfifo=stream-idle" build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
tail -120 build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
find build-real-b3-matrix/browser-main-menu-edge-decision-det-v1 -maxdepth 2 -type f -printf '%p %s\n'
rg -n "BOOT_MARK|EVIDENCE|error|Error|fail|timeout|TRACE|BROWSER_DIAGNOSTIC" build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log edge_det=build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log`
- Fixture assumptions: real browser runtime with selected MCPX, flash, EEPROM, and HDD assets; wasm from `build-wasm-pic`; deterministic browser mode on; edge-decision limit set to 4.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `browser_post_service_top_edge`; `edge-decision` marker presence; B4/B5/section-map preservation under the edge-decision trace build.

## Findings

- Result: negative evidence / early timeout. The browser runtime harness itself passed, but the emulated boot did not reach the dashboard-read/display baseline.
- `BROWSER_DIAGNOSTIC name=xbe_edge_decision_limit value=4` and `BROWSER_DIAGNOSTIC_APPLY name=xbe_edge_decision_limit value=4 target=/xemu-fixtures/xbe_edge_decision_limit.txt` prove the fixture plumbing applied.
- No `BOOT_MARK b6 edge-decision` markers were emitted.
- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- `DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker`.
- `DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=missing-section-map-marker`.
- `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker`.
- `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-stream-idle-transition`; browser stream-idle, watched reads/writes, service, and IRET fields were all missing.
- `POST_SERVICE_EDGE_DECISION_COMPARE result=pass ... classifications=baseline:useful-post-service-edge,edge_det:missing-stream-idle-boundary ... top_edges=baseline:0x80030e84->0x80030f31,edge_det:none`.
- The runtime transcript shows repeated `BOOT_MARK b6 deterministic=timer-pump ... reason=deterministic-blocked ... entry_ready=no progress=no` until `BOOT_SMOKE_RESULT reason=browser-main-timeout`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Yes. The run preserved only early browser runtime/B3 setup evidence; it regressed before dashboard read/load, B4 display capture, section-map, stream-idle, post-service edge, and edge-decision tracing.

## Decision

- Status: negative evidence
- Why: the trace build and fixture key are present, but this run cannot answer the intended post-service branch question because it never reaches the post-service or stream-idle boundary.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then revise the runtime setup before another run. The immediate candidate is to separate edge-decision tracing from deterministic scheduling changes, because the marker plumbing applied but deterministic mode blocked before `entry_ready`.
