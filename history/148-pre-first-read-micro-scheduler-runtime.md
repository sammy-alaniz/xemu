# Pre-First-Read Micro-Scheduler Runtime

## Purpose

- One new fact this run was supposed to produce: whether the opt-in `pit-pre-first-read-micro-scheduler` mode can produce normal browser tick-block completion before the first watched `0x0003a890` read consumes zero.

## Command(s)

```sh
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

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime-combined.log \
  --require-context browser-runtime
```

## Inputs And Artifacts

- Runtime log:
  `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log`
- Combined log: not produced; read-evidence combine failed before output.
- Native reference:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Rebuilt wasm: `build-wasm-pic/qemu-system-i386.wasm`

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_first_read_tick_block_completions_browser`

## Findings

- Result: negative evidence, but not at the intended boundary.
- The escalated harness started and completed with `BROWSER_RUNTIME_SMOKE result=pass ... boot_result=timeout`.
- Runtime evidence passed only at the B3/browser-harness level:
  `BROWSER_RUNTIME_EVIDENCE result=pass`.
- The log has only 153 lines and never reaches dashboard read/load, section-map, entry-ready, PFIFO stream-idle, IRET, scheduler, TCG timer-pump, tick-block, or edge-decision markers.
- Display capture fails:
  `DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker`.
- Strict dashboard evidence fails earlier than the usual B6 failure:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-read-marker`.
- The compact scheduler marker never appears:
  no `BOOT_MARK b6 scheduler=pre-first-read`.
- The pre-service comparator is not comparable:
  `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-stream-idle-transition`.
- The post-service edge comparator is not comparable:
  `POST_SERVICE_WATCH_EDGE_COMPARE result=fail divergence=missing-browser-pre-edge,browser-post-edge`.
- Dashboard read combiner fails:
  `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=fail reason=read-evidence-failed`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Yes relative to the same-origin baseline: B3/browser runtime evidence still passes, but B4 display capture, dashboard read/load, entry-ready, section-map, stream-idle, IRET, and the usual B6 boundary are all missing.

## Decision

- Status: negative evidence
- Why: the new before-interrupt pump-site mode regresses before entry-ready and the scheduler never activates, so `pre_first_read_tick_block_completions_browser` is not measured.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/145` approved exactly one runtime; this run consumed it and shows the implementation shape is too broad or too early even before the compact scheduler can start.

## Next Step

- Narrow follow-up: run the required loop check before any code change. Ask whether the next field should be `pre_entry_before_interrupt_site_overhead` or a narrower code fix that makes the before-interrupt site inactive until the scheduler is armed, without disabling the existing after-TB/ready-edge baseline before entry-ready.
