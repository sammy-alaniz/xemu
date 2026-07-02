# Timer Opportunity Limit8 Plumbed

## Purpose

- One new fact this run was supposed to produce: whether an explicitly plumbed
  low timer-opportunity limit preserves the first watched read while retaining
  the pre-stream `wait-not-pfifo-empty` blocker signal.

## Command(s)

```sh
node --check browser/xbox-boot/worker.js
node --check browser/xbox-boot/main.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
bash -n scripts/xbox-browser-runtime-smoke.sh
git diff --check -- \
  browser/xbox-boot/worker.js \
  browser/xbox-boot/main.js \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  scripts/xbox-browser-runtime-smoke.sh \
  xemu-xbe.c \
  history/31-timer-opportunity-limit-plumbing-loop-check.md

mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1

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
XEMU_BROWSER_RUNTIME_PORT=8827 \
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
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log \
  2>&1

rg -n "BROWSER_DIAGNOSTIC name=xbe_timer_opportunity_limit|BROWSER_DIAGNOSTIC_APPLY name=xbe_timer_opportunity_limit|BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_TRANSCRIPT" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-iret-frame-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log
```

## Inputs And Artifacts

- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-plumbed-v1/browser-runtime.log`
- Native comparator baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser plumbing changes:
  `browser/xbox-boot/worker.js`,
  `browser/xbox-boot/main.js`,
  `scripts/xbox-browser-runtime-firefox-bidi.mjs`,
  `scripts/xbox-browser-runtime-smoke.sh`
- Rebuilt wasm from the earlier timer-opportunity C fix:
  `build-wasm-pic/qemu-system-i386.js`

## Expected Field(s)

- `browser_pre_stream_timer_opportunities`, as the setup field proving the
  browser C-side limit was truly applied.
- `pre_service_browser_first_watch_read_ticks`, as the main loop-guard field.

## Findings

- Static JS/shell checks passed.
- The browser page emitted:
  `BROWSER_DIAGNOSTIC name=xbe_timer_opportunity_limit value=8`.
- The browser worker emitted:
  `BROWSER_DIAGNOSTIC_APPLY name=xbe_timer_opportunity_limit value=8 target=/xemu-fixtures/xbe_timer_opportunity_limit.txt`.
- Runtime summary emitted `trace_xbe_timer_opportunity_limit=8`.
- B5 runtime evidence passed:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- B4 display capture passed with hash
  `e3d330cca82bbe2aa91019b3de1fc1e5751aedca935ef6683d0153df7811d255`.
- Section-map evidence passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ... mapped_entry_rows=1`.
- Pre-stream comparator passed as a diagnostic comparison:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=pass divergence=browser-lacks-pre-stream-vector-service`.
- The low limit truly applied:
  `browser_pre_stream_timer_opportunities=8`.
- All eight browser opportunities were expired but not ready:
  `browser_pre_stream_timer_opportunity_ready=0`,
  `browser_pre_stream_timer_opportunity_expired=8`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`.
- First opportunity:
  `line=1182 ready=no reason=wait-not-pfifo-empty eip=0x80014f3d irq=0x00000000 wait_op=vblank-suppress virtual_expired=yes watch_ticks=0`.
- Last opportunity:
  `line=1259 ready=no reason=wait-not-pfifo-empty eip=0x80024216 irq=0x00000000 wait_op=vblank-suppress virtual_expired=yes watch_ticks=0`.
- Browser first watched read returned:
  `browser_first_watch_read_line=2519`,
  `browser_first_watch_read_edge=0x80014f32->0x80030e84`,
  `browser_first_watch_read_value=0x00000000`,
  `browser_first_watch_read_ticks=0`.
- Native first watched read remains 136 ticks, so
  `first_watch_read_tick_delta=136`.
- Browser still has no pre-stream PIT rising edge, main-loop timer progress,
  PIC ack `0x30`, vector `0x30` service, or IRET before PFIFO stream-idle.
- Browser post-stream vector `0x30` service returned:
  `browser_post_stream_service30=2`.
- IRET comparator passed structurally but reports a different return target
  versus the native graphic-update baseline:
  `IRET_FRAME_COMPARE result=pass divergence=interrupt-return-target-mismatch`.
- B6 still does not pass. The dashboard checker failed on this non-combined
  diagnostic log with `reason=missing-xbe-read-complete-marker`.

## Decision

- Status: current diagnostic support
- Why: this is the first low-perturbation artifact that proves the
  timer-opportunity limit is plumbed, preserves the first watched read, and
  explains the pre-stream tick gap more sharply: browser has expired timer work
  before stream-idle, but the current readiness gate keeps it from dispatching
  until PFIFO becomes empty.

## Next Step

- Run the required post-history sub-agent loop check.
- If approved, update `goal.md` and `AGENTS.md` current-boundary notes to make
  this plumbed limit8 artifact the focused timer-opportunity diagnostic, while
  keeping `browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
  as the fuller CPU-flow baseline unless a combined low-limit artifact is
  produced.
- The next technical slice should inspect or instrument the readiness gate that
  maps expired pre-stream timer work to `reason=wait-not-pfifo-empty`, rather
  than rerunning host-env-only limits or broad timer-pump variants.
