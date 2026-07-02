# Deterministic Browser M1 V1

## Purpose

- One new field this code slice and run could change or explain:
  `browser_first_watch_read_ticks`.
- Secondary gate:
  `browser_dashboard_xbe_executed` must still be strict and must not be faked.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-main-menu-deterministic-m1-v1

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
NODE_PATH= \
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_BROWSER_RUNTIME_MODE=real \
XEMU_BROWSER_RUNTIME_EXPECT_B3=1 \
XEMU_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_BROWSER_RUNTIME_BROWSER=firefox \
XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic \
XEMU_BROWSER_RUNTIME_PORT=8832 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BROWSER_BOOT_DETERMINISTIC=1 \
XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log \
  > build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/b6-current-boundary.txt \
  2>&1
```

## Inputs And Artifacts

- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Browser runtime log:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`
- Boundary summary:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1/b6-current-boundary.txt`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Expected Field(s)

- `browser_first_watch_read_ticks`
- `browser_dashboard_xbe_executed`

## Findings

- The WASM build passed through the podman container.
- Browser runtime evidence still passes:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- Display evidence still passes:
  `DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=47ce7a8e124d97a6b6cbcf5d5facd011af55a251bf562a9d1436fd16e15a9309`.
- Section-map evidence still passes:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... mapped_entry_rows=1`.
- The browser harness applied the new deterministic flags:
  `browser_boot_deterministic=1` and
  `browser_boot_deterministic_timer_steps=1`.
- The new source produced pre-stream timer progress:
  `main-loop=timers source=browser-deterministic-pump` at lines 1275, 1292,
  1307, and 1326.
- Primary metric improved:
  `pre_service_browser_first_watch_read_ticks` moved from 0 to 2.
- Native is still far ahead:
  `pre_service_native_first_watch_read_ticks=136`,
  `pre_service_first_watch_read_tick_delta=134`.
- Strict B6 still fails:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`
  and `B6_CURRENT_BOUNDARY_RESULT result=fail ... browser_xbe_executed=no`.
- The run still emits only detector proof, not strict execution:
  `dashboard=xbe-executed-detector-proof ... result=pass`.
- The first rejected strict candidate remains:
  `dashboard=xbe-exec-section-miss ... reason=high-alias-phys-mismatch`.
- New regression:
  `POST_SERVICE_WATCH_EDGE_COMPARE result=fail
  divergence=missing-browser-post-edge`, with browser missing the prior
  useful `0x80030e84->0x80030f31` post-service edge.
- The boundary helper reports:
  `current_boundary=post-idle-post-service-cpu-flow` and
  `next=restore-browser-main-loop-timer-progress`.

## Decision

- Status: partial M1 progress.
- Why:
  the deterministic path changed the target field in the right direction
  without weakening strict dashboard execution, but it does not complete B6 and
  it regresses the post-service edge that the previous ready-edge plus host
  fallback baseline preserved.

## Next Step

- Run the required loop check for this history entry.
- If it approves, revise deterministic mode so its timeline/log cap starts at
  dashboard entry-ready and its timer progress preserves the post-service
  `0x80030e84->0x80030f31` edge while keeping
  `browser_first_watch_read_ticks > 0`.
