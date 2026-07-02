# Deterministic Warmup1 Browser Runtime

## Purpose

- One new field this run was supposed to change or explain:
  `post_service_watch_edge`.
- Guardrail:
  keep `pre_service_browser_first_watch_read_ticks` above 0 if possible.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1

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
XEMU_BROWSER_RUNTIME_PORT=8833 \
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
XEMU_BROWSER_BOOT_DETERMINISTIC_WARMUP_PROGRESS_LIMIT=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log \
  > build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/b6-current-boundary.txt \
  2>&1
```

## Inputs And Artifacts

- Browser runtime log:
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log`
- Boundary summary:
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1/b6-current-boundary.txt`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Expected Field(s)

- `post_service_watch_edge`
- `pre_service_browser_first_watch_read_ticks`

## Findings

- Browser runtime, display, and section-map evidence still pass.
- The harness applied:
  `browser_boot_deterministic=1`,
  `browser_boot_deterministic_timer_steps=1`, and
  `browser_boot_deterministic_warmup_progress_limit=1`.
- The split-cap code restored the old ready-edge/host-fallback sources:
  `source=browser-ready-edge-qemu-pump` and
  `source=browser-headless-host-pump-bounded`.
- Warmup produced only one pre-stream deterministic timer event:
  `source=browser-deterministic-pump` at line 1268.
- This did not restore the target edge:
  `POST_SERVICE_WATCH_EDGE_COMPARE result=fail
  divergence=missing-browser-pre-edge,browser-post-edge`.
- It also regressed the tick metric from the previous deterministic run:
  `PRE_SERVICE_TICK_GAP_COMPARE result=fail
  divergence=missing-first-watch-read`.
- The boundary helper reports:
  - `pre_service_browser_first_watch_read_ticks=none`
  - `pre_service_browser_first_timer_watch_ticks=1`
  - `browser_first_watch_write_ticks=1`
  - `browser_post_service_top_edge=0x8001b02f->0x8001b030`
  - `post_service_watch_edge=fail`
  - `next=converge-browser-post-service-flow`
- Strict dashboard execution still fails:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.

## Decision

- Status: negative evidence.
- Why:
  a one-event deterministic warmup is too small or badly placed. It avoids the
  two-tick post-service branch regression from history 64, but it loses the
  watched read entirely and does not recover the useful post-service edge.

## Next Step

- Run the required loop check.
- If it approves, stop varying raw warmup count alone. The next field should be
  a CPU-flow field, for example why the browser with one warmup event transitions
  to `0x8001b02f->0x8001b030` instead of reaching the shared
  `0x80014f32->0x80030e84` read after stream idle.
