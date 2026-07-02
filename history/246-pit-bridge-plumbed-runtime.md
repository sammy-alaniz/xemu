# PIT Bridge Plumbed Runtime

## Purpose

- One new fact this run was supposed to produce: `pit_attributed_pre_stream_bridge_preserves_post_service_edge`.

## Command(s)

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_PORT=8837 \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=90000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
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
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE=1 \
XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT=1 \
scripts/xbox-real-b3-matrix.sh

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log pit_bridge=build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/browser-runtime.log \
  > build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/b6-current-boundary.txt 2>&1
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/browser-runtime.log`
- Combined output: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1-combined.log`
- Boundary reducer output: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-plumbed-v1/b6-current-boundary.txt`
- Fixture assumptions: same real dashboard/HDD assets as the stable ready-edge host4 baseline; the new PIT bridge settings were applied through browser fixtures.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `pit_attributed_pre_stream_bridge_preserves_post_service_edge`
  - `pre_service_browser_first_watch_read_ticks`
  - `browser_post_service_top_edge`

## Findings

- Result: activation occurred, but preservation failed.
- Browser runtime smoke passed and timed out as expected for the current B6 failure:
  - `BROWSER_RUNTIME_SMOKE result=pass ... boot_result=timeout`
  - `BROWSER_RUNTIME_TRANSCRIPT result=pass ... browser_boot_pit_pre_stream_bridge=1 browser_boot_pit_pre_stream_bridge_limit=1`
- B4 display capture passed:
  - final captured hash `513ead410577a139210f81f52d4bdacdb7011b6c254d344ee0242cd08636ae92`
- Dashboard read/load/entry-ready/section-map evidence was preserved enough for the B6 boundary helper:
  - `DASHBOARD_SECTION_MAP_EVIDENCE result=pass`
  - strict B6 still failed at `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`
- PIT bridge activation was proven:
  - `main-loop=timers source=browser-pit-prestream-bridge ... timer_progress=yes`
  - the bridge fired before PFIFO stream-idle with watched value `0x00000000`.
- The first watched read improved only to 1 tick and remained 135 ticks behind native:
  - native first read: `0x80014f5f->0x80030e84`, 136 ticks
  - browser first read: `0x80014f32->0x80030e84`, 1 tick
  - `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup ... first_watch_read_tick_delta=135`
- Post-service preservation regressed:
  - `POST_SERVICE_WATCH_EDGE_COMPARE result=fail divergence=missing-browser-post-edge`
  - native post edge: `0x80030e84->0x80030f31`
  - browser post edge: none
  - edge-decision helper classified the bridge as `watch-write-without-focused-read`
  - baseline top edge: `0x80030e84->0x80030f31`
  - PIT bridge top edge: `0x80030e4c->0x80030f45`
- The boundary reducer's final result stayed failed:
  - `B6_CURRENT_BOUNDARY_RESULT result=fail reason=required-diagnostic-failed b6_reason=missing-xbe-executed-marker`
  - `browser_xbe_executed=no`
  - `post_service_watch_edge=fail`
  - `post_idle_timer_divergence=main-loop-timer-progress-count-mismatch`
  - `next=converge-browser-post-service-flow`
- The source-tagged scheduler fields are now populated in the reducer:
  - `first_kick_after_last_opportunity_source=nv-user-dma-put`
  - `scheduler_events_before_first_opportunity=0`
  - `kick_events_before_first_opportunity=0`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/browser runtime/read/section-map/stream-idle/IRET evidence exists, but the focused post-service watch edge regressed and the browser still did not execute the dashboard XBE.

## Decision

- Status: negative evidence
- Why: the branch-exit rule from `history/245` applies. The bridge activated, but it did not preserve the useful `0x80030e84->0x80030f31` post-service edge and did not materially close the 136-tick native gap. Do not tune the PIT bridge limit or run another bridge runtime.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/245-pit-bridge-plumbed-runtime-loop-check.md` approved exactly one plumbed runtime and warned to quarantine the bridge if activation occurred with preservation regression.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the pre-run loop check said the method was close to a PIT-bridge loop and required a branch-exit decision instead of additional runtime variants.
- If yes, process adjustment for next 2-3 turns: stop PIT-bridge limit tuning; use the new `nv-user-dma-put` scheduler-source result and the post-service-edge regression to choose a different causal code path.

## Next Step

- Narrow follow-up: run the required post-history sub-agent loop check with progress-method critique. Ask it to decide whether the next mode should be PIT bridge quarantine/code cleanup, static inspection of `nv-user-dma-put` ordering, or a deterministic scheduler design change.
