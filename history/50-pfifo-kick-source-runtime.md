# PFIFO Kick Source Runtime

## Purpose

- One new fact this run was supposed to produce: identify whether any PFIFO kick
  source exists before the expired timer-opportunity window, and identify the
  first PFIFO kick source after that window.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1

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
XEMU_BROWSER_RUNTIME_PORT=8830 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log \
  2>&1

scripts/xbox-pfifo-scheduler-state-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-pfifo-pusher-entry-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log`
- Output directory/log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log`
- Fixture assumptions: real MCPX, flash, EEPROM, and HDD paths from `AGENTS.md`
  were used locally and remain untracked.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `kick_sources_before_first_opportunity`,
  `first_kick_after_last_opportunity_source`.

## Findings

- Result: pass for the focused diagnostic; B6 still fails as expected.
- Important marker/comparator lines:
  - `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`
  - `DISPLAY_CAPTURE_EVIDENCE result=pass ...
    hash=ad10d4afa5e13cc319618d7a1d5b1678fd7f00d55f1750446a0609aa890158af`
  - `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... mapped_entry_rows=1`
  - `PFIFO_SCHEDULER_STATE_CLASSIFY result=pass
    divergence=no-pfifo-scheduler-event-before-first-opportunity`
  - `scheduler_events_before_first_opportunity=0`
  - `kick_events_before_first_opportunity=0`
  - `kick_sources_before_first_opportunity=none`
  - `first_scheduler_after_last_opportunity_line=1385`
  - `first_scheduler_after_last_opportunity_op=kick`
  - `first_scheduler_after_last_opportunity_kick_source=nv-user-dma-put`
  - `first_kick_after_last_opportunity_source=nv-user-dma-put`
  - `first_kick_after_last_opportunity_delta=130`
  - `first_pusher_enter_line=1393`
  - `first_pusher_enter_reason=entry-gates-open-with-dma-pending`
  - `first_pusher_enter_dma_to_put=4864`
  - `PRE_STREAM_TICK_SOURCE_COMPARE result=pass
    divergence=browser-lacks-pre-stream-vector-service`
  - `browser_pre_stream_timer_opportunities=8`
  - `browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window`
  - `browser_first_watch_read_ticks=0`
  - `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass ... context=browser-runtime`
  - `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`
  - `B6_CURRENT_BOUNDARY_RESULT result=pass ... b6=fail
    b6_reason=missing-xbe-executed-marker ... browser_xbe_executed=no`
- Additional boundary signal:
  - The boundary helper reports `browser_main_loop_timer_progress_events=3`,
    `browser_main_loop_timer_max_memory_watch_ticks=1`, and
    `browser_post_service_top_edge=0x80030e4c->0x80030f60`.
  - The primary pre-service gap did not move:
    `pre_service_browser_first_watch_read_ticks=0` versus native `136`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  No for B4/B5/read/load/entry-ready/section-map. Stream-idle remains present.
  IRET remains diagnostically present, but the current native graphic-update
  comparator still reports `iret_divergence=interrupt-return-target-mismatch`.

## Decision

- Status: current
- Why: the run answered the intended source field. There is no PFIFO kick before
  the expired timer opportunities; the first kick after that window is from the
  guest channel `NV_USER_DMA_PUT` write. Repeating PFIFO scheduler, pusher,
  window-publication, or timer-opportunity classifiers without a new question
  would now be a loop.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history 49 approved exactly this runtime because
  the source-tagged marker could populate
  `first_kick_after_last_opportunity_source`.

## Next Step

- Narrow follow-up: run the required sub-agent loop check for this history
  entry. If it approves, update `goal.md` and `AGENTS.md` to make
  `nv-user-dma-put` the current PFIFO kick-source boundary and choose the next
  field. The likely next field is why no earlier guest `NV_USER_DMA_PUT` write
  occurs before the expired timer-opportunity window, or whether the guest DMA
  PUT publication itself is gated by the same pre-service timing gap.
