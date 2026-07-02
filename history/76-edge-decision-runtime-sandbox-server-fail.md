# Edge Decision Runtime Sandbox Server Fail

## Purpose

- One new fact this run was supposed to produce: populate bounded
  `edge-decision` markers to explain `browser_post_service_top_edge`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-main-menu-edge-decision-det-v1

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin NODE_PATH= XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' XEMU_BROWSER_RUNTIME_MODE=real XEMU_BROWSER_RUNTIME_EXPECT_B3=1 XEMU_BROWSER_RUNTIME_DRIVER=firefox-bidi XEMU_BROWSER_RUNTIME_BROWSER=firefox XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic XEMU_BROWSER_RUNTIME_PORT=8834 XEMU_BROWSER_RUNTIME_BOOT_MS=90000 XEMU_BROWSER_RUNTIME_TIMEOUT_MS=150000 XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT=1 XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8 XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4 XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump XEMU_BROWSER_BOOT_DETERMINISTIC=1 XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=1 XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 scripts/xbox-browser-runtime-smoke.sh > build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log 2>&1
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log`
- Fixture assumptions: real local MCPX, flash, EEPROM, and HDD assets.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: failed before browser runtime started.
- Important marker/comparator lines:
  - `BOOT_FIXTURE_RESULT result=pass`
  - `BROWSER_RUNTIME_SMOKE result=fail reason=server-exited`
  - Python local server failed with
    `PermissionError: [Errno 1] Operation not permitted`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; the local browser server could not bind a socket, so emulation
  did not start.

## Decision

- Status: failed run
- Why: sandbox denied local server socket creation. This is an execution
  environment failure, not B6 evidence.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history/75 approved the marker-populating runtime;
  this run did not reach that experiment.

## Next Step

- Narrow follow-up: run the required loop-check, then rerun the same focused
  browser runtime with escalated permissions so the local server and browser can
  start.
