# 180. Before-Interrupt Quarantine Runtime Restored Boundary

## Purpose

Run the single restoration browser runtime approved by
`history/179-before-interrupt-quarantine-runtime-loop-check.md` after disabling
the micro-scheduler before-interrupt hook.

## Commands

```sh
mkdir -p build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1

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
  > build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
rg -n 'dashboard=xbe-read|dashboard=xbe-loaded|section-map|entry-ready|pfifo=stream-idle|scheduler=pre-first-read|tcg=timer-pump|edge-decision|tick-block=complete|memory-watch|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack' \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
rg -n 'dashboard=xbe-executed|dashboard=xbe-read |dashboard=xbe-read-complete|dashboard=xbe-loaded|dashboard=xbe-read-progress|scheduler=pre-first-read|scheduler=pre-first-read-gate|tcg=timer-pump|memory-watch|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result' \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
tail -100 build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
wc -l build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
```

## Inputs / Artifacts

- Rebuilt WASM artifact: `build-wasm-pic/qemu-system-i386.js`
- Runtime log:
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log`
- Known-good browser origin/port: `http://127.0.0.1:8846/browser/xbox-boot/`

## Loop-Guard Field

- `micro_scheduler_branch_quarantined_restores_dashboard_read_load`

## Findings

The before-interrupt quarantine restored the useful browser boundary.

- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`
- `DISPLAY_CAPTURE_EVIDENCE result=pass ... source=browser-framebuffer`
- Strict dashboard loaded check still fails:
  `reason=missing-xbe-read-complete-marker`
- `dashboard=xbe-loaded` appears at line 1025.
- `dashboard=xbe-section-map phase=entry-ready` appears at line 1145.
- `dashboard=xbe-executed-detector-proof result=pass subject=entry` appears at
  line 1152, but this is not a strict executed marker and does not satisfy B6.
- Memory watch installs at line 1153.
- PFIFO stream-idle transition and boundary appear at lines 2625 and 2628.
- The browser reaches PIC ack and hard-IRQ service for vector `0x30`.
- Four bounded host-pump progress events appear after stream-idle.
- No `scheduler=pre-first-read`, `scheduler=pre-first-read-gate`, or
  `tcg=timer-pump` marker appears.
- No strict `dashboard=xbe-executed` marker appears.
- The log has 2707 lines, not the previous 375-line early-timeout shape.

The read-progress sequence reaches `contiguous_bytes=172032` for an image size
of `175080`, but the read-complete marker is still missing.

## Decision

The before-interrupt hook was the perturbing part of the micro-scheduler branch.
Keeping it quarantined restores B4, XBE load/entry-ready, section-map, PFIFO
stream-idle, visible browser frames, and IRQ service evidence. This is not B6.

## Next Step

Run the required bounded loop check before deciding whether to keep the
before-interrupt hook quarantined as the restored baseline or quarantine the
whole micro-scheduler mode path.
