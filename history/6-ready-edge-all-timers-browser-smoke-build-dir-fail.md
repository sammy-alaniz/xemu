# Ready-Edge All-Timers Browser Smoke Build Dir Fail

## Purpose

- One new fact this run was supposed to produce: whether the opt-in `pfifo-ready-edge-qemu-pump-all` browser run changes `pre_service_browser_first_watch_read_ticks`.

## Command(s)

```sh
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
XEMU_BROWSER_RUNTIME_BUILD_DIR=build-wasm-pic \
XEMU_BROWSER_RUNTIME_PORT=8822 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump-all \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v1/browser-runtime.log \
  2>&1
```

## Inputs And Artifacts

- Baseline native log: not consumed by the failed smoke.
- Baseline browser log: not consumed by the failed smoke.
- Output log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v1/browser-runtime.log`
- Fixture assumptions: local real B6 fixtures from `goal.md`; fixture preflight passed.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: failed before emulation because the browser build artifacts were requested from the wrong URL.
- The runtime log shows `BROWSER_ARTIFACT kind=js ... /browser/xbox-boot/build-wasm-pic/qemu-system-i386.js status=404` and the same 404 for wasm.
- `BROWSER_BOOT_ERROR` reports dynamic import failure, followed by `BROWSER_RUNTIME_SMOKE result=fail reason=missing-b3-marker`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; QEMU wasm never loaded.

## Decision

- Status: failed run
- Why: command used `XEMU_BROWSER_RUNTIME_BUILD_DIR=build-wasm-pic`; this script expects the page-relative default `../../build-wasm-pic` for this repo layout.
- Independent critique used: no

## Next Step

- Narrow follow-up: rerun the exact all-timers browser smoke with `XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic`.
