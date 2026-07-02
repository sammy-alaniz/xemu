# 224. Pre-TB Scheduler Runtime Sandbox Server Fail

## Purpose

Run the one preservation-gated browser runtime approved by
`history/223-pre-tb-scheduler-runtime-loop-check.md`.

The one field this run could change was `browser_first_watch_read_ticks`.

## Commands

```sh
mkdir -p build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1

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
XEMU_BROWSER_RUNTIME_PORT=8848 \
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
  > build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log \
  2>&1

sed -n '1,220p' build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
tail -120 build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
wc -l build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
```

## Inputs and Artifacts

- Built WASM artifact from `history/222-pre-tb-scheduler-build-pass.md`
- Runtime log:
  `build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`

## Findings

The runtime exited immediately with status 1 before emulation.

The fixtures passed, but the browser runtime server failed to start:

```text
BROWSER_RUNTIME_SMOKE result=fail reason=server-exited log=/tmp/xemu-browser-runtime-smoke.EEWgSJ/server.log
PermissionError: [Errno 1] Operation not permitted
```

The traceback shows the failure at Python socket creation in
`serve-xbox-browser-boot.py`.

The log has 19 lines. This is a sandbox socket/setup failure, not a B6 runtime
result and not evidence about `browser_first_watch_read_ticks`.

## Decision

`browser_first_watch_read_ticks=not-tested-sandbox-server-fail`

## Next Step

Run the required loop check, then rerun the exact same browser runtime with
escalated permissions so the local server can create its socket.
