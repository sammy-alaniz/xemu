# Timer Opportunity Runtime Pre-Entry Mutex Fail

## Purpose

- One new fact this run was supposed to produce: whether the rebuilt current ready-edge-host4 browser runtime emits pre-stream timer-opportunity evidence before the first watched read.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1

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
XEMU_BROWSER_RUNTIME_PORT=8824 \
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
XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1/browser-runtime.log \
  2>&1

tail -n 120 build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1/browser-runtime.log

rg -n "BROWSER_RUNTIME_SMOKE|BOOT_MARK b6 headless=timer-opportunity|error|Error|failed|FAILED|404|wasm|qemu-system-i386" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1/browser-runtime.log

wc -l build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1/browser-runtime.log
```

## Inputs And Artifacts

- Browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v1/browser-runtime.log`
- Rebuilt wasm artifacts under `build-wasm-pic`
- Local real B6 fixtures from `goal.md`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, via new pre-stream timer-opportunity evidence.

## Findings

- Result: fail before B3.
- Browser assets loaded and fixture validation passed, but the run aborted immediately after the first `headless=timer-pump-gate` marker.
- Abort line: `Aborted(Assertion failed: mutex->initialized, at: ../util/qemu-thread-posix.c,92,qemu_mutex_lock_impl)`.
- `BROWSER_RUNTIME_SMOKE result=fail reason=missing-b3-marker`.
- No `headless=timer-opportunity` marker was emitted.
- The likely issue is that `xemu_xbe_boot_trace_observe_browser_timer_opportunity()` tries to read the NV2A wait snapshot before `entry_ready`, which calls a mutex that has not been initialized yet.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? The run never reached B3, so this is instrumentation startup failure, not B6 evidence.

## Decision

- Status: failed-run support
- Why: the marker must avoid pre-entry wait snapshot locking or initialize that lock before first use.
- Independent critique used: yes

## Next Step

- Run the required post-history sub-agent loop check, then fix the marker to skip wait-state and CPU/context sampling until `entry_ready=yes`, or otherwise make the lock initialization safe before pre-entry sampling.
