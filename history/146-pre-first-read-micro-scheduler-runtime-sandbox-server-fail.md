# Pre-First-Read Micro-Scheduler Runtime Sandbox Server Fail

## Purpose

- One new fact this run was supposed to produce: whether one same-origin browser runtime with `pit-pre-first-read-micro-scheduler` reaches the B6 boundary and reports the new scheduler stop reason.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1

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
XEMU_BROWSER_RUNTIME_PORT=8846 \
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
XEMU_BOOT_TRACE_XBE_TICK_BLOCK_LIMIT=256 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-pre-first-read-micro-scheduler \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_PRE_FIRST_READ_SCHEDULER_TB_BUDGET=512 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log \
  2>&1
```

## Inputs And Artifacts

- Runtime log:
  `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: same-origin port `8846`, rebuilt `build-wasm-pic`, real local Xbox assets.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `runtime_harness_status`

## Findings

- Result: failed before emulator/browser runtime.
- The log has 19 lines and only fixture validation plus server startup failure.
- Important line:
  `BROWSER_RUNTIME_SMOKE result=fail reason=server-exited log=/tmp/xemu-browser-runtime-smoke.Dq6sLX/server.log`
- Server error:
  `PermissionError: [Errno 1] Operation not permitted` while constructing `ThreadingHTTPServer`.
- No B3/B4/B5/B6, scheduler, memory-watch, PFIFO, IRET, or display evidence was produced.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; the server failed before emulation started.

## Decision

- Status: failed run
- Why: sandbox socket permissions blocked the same-origin browser server.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then retry the exact same runtime with escalation if approved. The retry can change `runtime_harness_status` first and, if the harness starts, `pre_first_read_tick_block_completions_browser`.
