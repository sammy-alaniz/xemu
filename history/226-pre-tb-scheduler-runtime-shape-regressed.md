# 226. Pre-TB Scheduler Runtime Shape Regressed

## Purpose

Run the one preservation-gated browser runtime approved by
`history/223-pre-tb-scheduler-runtime-loop-check.md` and retried with
escalation after `history/225-pre-tb-scheduler-runtime-escalation-loop-check.md`.

The one field this run could change was `browser_first_watch_read_ticks`, but
only if the preservation gates passed.

## Commands

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

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
rg -n 'BROWSER_RUNTIME|DISPLAY_CAPTURE|dashboard=xbe-read|dashboard=xbe-loaded|dashboard=xbe-section-map|entry-ready|pfifo=stream-idle|scheduler=pre-first-read|tcg=timer-pump|edge-decision|tick-block=complete|memory-watch|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack|dashboard=xbe-executed|BOOT_SMOKE_RESULT' \
  build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
tail -80 build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log
```

## Inputs and Artifacts

- Built WASM artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Runtime log:
  `build-real-b3-matrix/browser-pre-tb-scheduler-owner-v1/browser-runtime.log`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`
- B4/B5/read/load/entry-ready/section-map preservation

## Findings

The runtime command exited with status 0, and the browser runtime evidence
check passed:

```text
BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout
```

The preservation gates failed immediately after that:

```text
DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker
DASHBOARD_SECTION_MAP_EVIDENCE result=fail reason=missing-section-map-marker
DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker
```

The transcript has only 154 lines. It reaches B0/B1/B2/B3 fixture and block
read evidence plus placeholder display scanouts, then times out:

```text
BOOT_SMOKE_RESULT reason=browser-main-timeout elapsed_ms=90073 exit=124
BROWSER_RUNTIME_TRANSCRIPT ... b4_marker=no display_capture=no
```

No dashboard read/load/entry-ready, PFIFO stream-idle, vector `0x30`
service/IRET, post-service edge, or strict `dashboard=xbe-executed` evidence
is present.

## Decision

`browser_first_watch_read_ticks=not-interpretable-shape-regressed`

The pre-TB scheduler owner runtime regressed before B4/B5/dashboard-read
preservation, so the primary tick field and any scheduler markers must not be
interpreted causally from this artifact.

## Next Step

Run the required loop check. The likely decision point is whether to stop the
pre-TB scheduler branch or revise only by quarantining/disabling this path
before returning to the stable baseline.
