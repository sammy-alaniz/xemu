# Timer Opportunity Limit8 Env Not Plumbed

## Purpose

- One new fact this run was supposed to produce: whether reducing
  `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT` to 8 would preserve the first
  watched read while retaining the pre-stream `wait-not-pfifo-empty`
  timer-opportunity signal.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1

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
XEMU_BROWSER_RUNTIME_PORT=8826 \
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
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log

scripts/xbox-iret-frame-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log
```

## Inputs And Artifacts

- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log`
- Native comparator baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Same rebuilt wasm from `history/28`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by restoring a concrete browser
  first watched read while retaining timer-opportunity blocker evidence.
- `browser_pre_stream_timer_opportunities`, expected to fall from 128 to 8 if
  the C-side limit override reached the browser wasm runtime.

## Findings

- B5 runtime evidence passed:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- B4 display capture passed with hash
  `5436364930b90469ac6f9633fd43b3e38192a670b50fda9f0cd3e22a76525c37`.
- Section-map evidence passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ... mapped_entry_rows=1`.
- Comparator result:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=fail divergence=missing-first-watch-read`.
- The intended low limit did not take effect:
  `browser_pre_stream_timer_opportunities=128` even though the host command set
  `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8`.
- The opportunity signal repeated the v2 finding:
  `browser_pre_stream_timer_opportunity_ready=0`,
  `browser_pre_stream_timer_opportunity_expired=128`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`.
- The browser still had no pre-stream PIT, main-loop timer progress, PIC ack
  `0x30`, vector `0x30` service, or IRET before stream-idle.
- The run still missed the first watched read and IRET pair:
  `first_watch_read_tick_delta=none`,
  `browser_first_watch_read_line=0`,
  `IRET_FRAME_COMPARE result=fail reason=browser-missing-iret-pair`.
- B6 still does not pass. The dashboard checker failed on this non-combined
  diagnostic log with `reason=missing-xbe-read-complete-marker`.

## Decision

- Status: negative evidence for host-env-only limiting
- Why: the no-code low-limit attempt answered a different useful question: the
  new C-side timer-opportunity limit is not currently plumbed from the host env
  into browser wasm, so no-code limit reduction cannot reduce perturbation.

## Next Step

- Run the required post-history sub-agent loop check.
- If approved, add browser-side plumbing for
  `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT` through the same fixture-file
  path used by other C-side browser diagnostics, then rebuild and rerun exactly
  one low-limit ready-edge-host4 probe.
