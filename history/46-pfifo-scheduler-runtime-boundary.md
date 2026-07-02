# PFIFO Scheduler Runtime Boundary

## Purpose

Populate `pfifo_scheduler_state_before_first_timer_opportunity` with a focused
browser runtime that includes the new `BOOT_MARK b6 pfifo=scheduler` markers.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1

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
XEMU_BROWSER_RUNTIME_PORT=8829 \
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
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log \
  2>&1

scripts/xbox-pfifo-scheduler-state-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-pfifo-pusher-entry-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1-combined.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log
```

## Inputs/Artifacts

- Raw browser runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log`
- Combined browser runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Rebuilt wasm:
  `build-wasm-pic/qemu-system-i386.js`

## Expected Field(s)

- `pfifo_scheduler_state_before_first_timer_opportunity`
- `pre_service_browser_first_watch_read_ticks`

## Findings

The wasm rebuild passed and compiled the changed PFIFO source:

```text
[4/5] Compiling C object libqemu-i386-softmmu.a.p/hw_xbox_nv2a_pfifo.c.o
[5/5] Linking target qemu-system-i386.js
```

B5 runtime evidence passed:

```text
BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout
```

B4 display capture passed:

```text
DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=623c5fe76747ebb49342cd2922f2c80040d8050d4db287e583466afa82401a25 source=browser-framebuffer
```

Section-map evidence passed:

```text
DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... context=browser-runtime phase=entry-ready ... mapped_entry_rows=1
```

The scheduler classifier answered the new field:

```text
PFIFO_SCHEDULER_STATE_CLASSIFY result=pass divergence=no-pfifo-scheduler-event-before-first-opportunity loop_guard_field=pfifo_scheduler_state_before_first_timer_opportunity xbe_loaded_line=1015 entry_ready_line=1134 first_opportunity_line=1162 last_opportunity_line=1242 timer_opportunities=8 scheduler_events=128 scheduler_events_before_first_opportunity=0 kick_events_before_first_opportunity=0 thread_events_before_first_opportunity=0 wait_before_first_opportunity=0 wake_before_first_opportunity=0 before_run_pusher_before_first_opportunity=0 first_scheduler_after_last_opportunity_line=1385 first_scheduler_after_last_opportunity_op=kick first_scheduler_after_last_opportunity_dma_get=0x03880000 first_scheduler_after_last_opportunity_dma_put=0x03881300 first_scheduler_after_last_opportunity_dma_to_put=4864 first_before_run_pusher_after_last_opportunity_line=1395 first_before_run_pusher_after_last_opportunity_delta=153 first_pusher_enter_line=1396 scheduler_markers_present=yes
```

The pusher-entry ordering remains consistent, shifted only by line numbers:

```text
PFIFO_PUSHER_ENTRY_CLASSIFY result=pass divergence=pusher-entry-after-opportunities first_opportunity_line=1162 last_opportunity_line=1242 last_pusher_not_entered_source=static-marker-contract last_pusher_not_entered_reason_before_first_opportunity=not-called-before-first-opportunity first_pusher_enter_line=1396 first_pusher_enter_reason=entry-gates-open-with-dma-pending first_pusher_enter_dma_to_put=4864
```

The pre-stream tick source comparison still shows the active tick gap:

```text
PRE_STREAM_TICK_SOURCE_COMPARE result=pass divergence=browser-lacks-pre-stream-vector-service first_watch_read_tick_delta=136 browser_pre_stream_timer_opportunities=8 browser_pre_stream_timer_opportunity_ready=0 browser_pre_stream_timer_opportunity_expired=8 browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window browser_first_watch_read_ticks=0
```

The raw runtime log still lacks appended read-complete proof, so the combiner was
used. The combined log restores the strict read/load/entry-ready checker path
and still fails B6 at the expected execution boundary:

```text
COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass ... context=browser-runtime
DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker
```

Boundary helper summary:

```text
B6_CURRENT_BOUNDARY_PFIFO_SCHEDULER_STATE result=pass divergence=no-pfifo-scheduler-event-before-first-opportunity scheduler_events_before_first_opportunity=0 first_scheduler_after_last_opportunity_line=1385 first_scheduler_after_last_opportunity_op=kick first_before_run_pusher_after_last_opportunity_line=1395 first_pusher_enter_line=1396 scheduler_markers_present=yes
```

The combined diagnostic still has `browser_first_watch_read_ticks=0` and B6
still fails at `missing-xbe-executed-marker`.

## Decision

Current focused evidence. The new boundary is earlier than PFIFO thread
wake/sleep details: there is no PFIFO scheduler event at all before the first
timer-opportunity window. The first scheduler event is a PFIFO kick after the
opportunity window, then thread wake and `before-run-pusher`.

## Next Step

Explain what produces the first post-opportunity PFIFO kick at line 1385 and why
no equivalent PFIFO kick/scheduler event exists before the expired timer
opportunities. The next narrow field should identify the kick source/order, not
rerun PFIFO scheduler, pusher-entry, PFIFO-window publication, or generic
pump/vblank modes.
