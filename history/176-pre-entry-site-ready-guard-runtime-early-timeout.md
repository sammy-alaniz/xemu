# 176. Pre-Entry Site-Ready Guard Runtime Early Timeout

## Purpose

Run the single controlled browser runtime retry approved by
`history/175-pre-entry-site-ready-runtime-loop-check.md` after reducing
pre-entry scheduler predicate work.

## Commands

```sh
mkdir -p build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1

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
  > build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
rg -n 'dashboard=xbe-read|dashboard=xbe-loaded|section-map|entry-ready|pfifo=stream-idle|scheduler=pre-first-read|tcg=timer-pump|edge-decision|tick-block=complete|memory-watch|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack' \
  build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
rg -n 'BROWSER_LOCATION|BROWSER_ARTIFACT|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result|ide=hdd|read_lba=4609024|read_lba=4609032|read_lba=4609192|BROWSER_BLOCK_READ|bmdma=start_dma' \
  build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
tail -80 build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
wc -l build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log
```

## Inputs / Artifacts

- Rebuilt WASM artifact: `build-wasm-pic/qemu-system-i386.js`
- Output log:
  `build-real-b3-matrix/browser-pre-entry-site-ready-guard-runtime-v1/browser-runtime.log`
- Known-good browser origin/port: `http://127.0.0.1:8846/browser/xbox-boot/`

## Loop-Guard Field

- `pre_entry_site_ready_side_effect_reduced`

## Findings

The retry failed at the hard-stop gate.

- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`
- `DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker`
- `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker`
- No `dashboard=xbe-read`, `dashboard=xbe-loaded`, entry-ready, section-map,
  PFIFO stream-idle, scheduler, TCG timer-pump, edge-decision, tick-block,
  hard-IRQ, IRET, or PIC-ack markers appeared.
- The log has 375 lines, matching the prior early-timeout shape.
- The run used the known-good origin on port `8846`.
- The run again stopped after `read_lba=4609024`, with browser block reads at
  offsets `2555904` and `2621440`.

This means the exact post-STI scheduler field is still untested. Reducing the
pre-entry site-ready predicate work did not restore dashboard read/load.

## Decision

Failed run. Per the loop-check criterion, do not tune this micro-scheduler branch
with another runtime retry.

## Next Step

Run the required bounded loop check. The proposed decision is to quarantine or
roll back the micro-scheduler plumbing before returning to the last restored
browser boundary.
