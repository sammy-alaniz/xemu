# Pre-First-Read Micro-Scheduler Armed Runtime

## Purpose

- One new fact this run was supposed to produce: whether the armed-only pre-first-read micro-scheduler site restores the prior browser boot boundary while allowing `scheduler=pre-first-read` markers to explain or move the first watched read tick count.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1
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
  > build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime-combined.log \
  --require-context browser-runtime
scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Combined output log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime-combined.log`
- Fixture assumptions: real browser runtime with Firefox BiDi, rebuilt wasm in `build-wasm-pic`, PCRTC vblank off, ready-edge host pump still capped at 4 progress events, memory watch on physical `0x0003a890` write access.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `scheduler_site_armed_only_restores_boundary`, `pre_first_read_scheduler_armed`, `pre_service_browser_first_watch_read_ticks`, and `missing-xbe-executed-marker`.

## Findings

- Result: boundary restored but the micro-scheduler did not arm.
- `BROWSER_RUNTIME_EVIDENCE result=pass`.
- `DISPLAY_CAPTURE_EVIDENCE result=pass` with framebuffer hash `1969be83106f02d15785501404d847e2f03cd24a02865d325970224f7bf1410c`.
- Raw dashboard loaded check failed before combining due to `missing-xbe-read-complete-marker`; the combiner produced the combined log successfully.
- Combined strict B6 check still failed: `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- No `BOOT_MARK b6 scheduler=pre-first-read` marker appeared.
- No `BOOT_MARK b6 tcg=timer-pump` marker appeared.
- `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup`.
- Pre-service native first watched read stayed at 136 ticks; browser first watched read stayed at 0 ticks; `pre_service_first_watch_read_tick_delta=136`.
- Browser first watched read edge remained `0x80014f32->0x80030e84` with value `0x00000000`.
- Browser first watched write immediately followed at `0x80030e84` with value `0x00000000`.
- Browser first timer source remained `browser-ready-edge-qemu-pump`, with timer watch ticks still 0.
- `POST_SERVICE_WATCH_EDGE_COMPARE result=pass divergence=pre-block-watch-value-mismatch`.
- The post-service block delta still matched: native enters `0x80030e84->0x80030f31` at 136 ticks and leaves at 137; browser enters at 0 and leaves at 1.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map/stream-idle did not regress. The focused pre-service comparator reported no browser IRET pair for this artifact, while the useful post-service watch edge remained present.

## Decision

- Status: negative evidence
- Why: the armed-only fix corrected the earlier over-broad before-interrupt pump regression and restored the useful browser boundary, but it did not move the primary metric. The scheduler marker never appeared, so this run cannot tell whether the checkpoint itself would help; it only proves the current arming predicate is too strict or is missing the actual close-to-read window.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the last loop check supported one runtime validation after the armed-only build. The next useful fact is no longer another full runtime repeat; it is why the scheduler did not arm.

## Next Step

- Narrow follow-up: add or inspect a bounded `scheduler=pre-first-read-gate` reason marker that can explain `scheduler_not_armed_reason` before running another browser runtime. The next probe should report the first close gate state before the watched read, including entry-ready, expired timer status, serviceable CPU state, edge-decision count, stream-idle state, and whether the watched read has already happened.
