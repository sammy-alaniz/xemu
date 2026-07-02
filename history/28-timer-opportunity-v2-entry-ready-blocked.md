# Timer Opportunity V2 Entry-Ready Blocked

## Purpose

- One new fact this run was supposed to produce: whether safe entry-ready
  browser timer-opportunity evidence exists before PFIFO stream-idle and before
  the first watched read of physical `0x0003a890`.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2

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
XEMU_BROWSER_RUNTIME_PORT=8825 \
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
XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log

scripts/xbox-iret-frame-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log
```

## Inputs And Artifacts

- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log`
- Native comparator baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Rebuilt wasm artifact: `build-wasm-pic/qemu-system-i386.js`
- Prior failed runtime entry:
  `history/26-timer-opportunity-runtime-pre-entry-mutex-fail.md`
- Prior loop check:
  `history/27-timer-opportunity-pre-entry-loop-check.md`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by explaining whether browser
  has safe entry-ready timer opportunities before PFIFO stream-idle.
- `browser_pre_stream_timer_opportunities`, as the diagnostic field showing
  whether the browser timer pump is being offered work before stream-idle.

## Findings

- The wasm rebuild passed and linked `qemu-system-i386.js`.
- The runtime smoke passed B5 evidence:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- B4 display capture passed with latest hash
  `cdd721a24dd8458bc15e53c249d11719bf62bc80624f3f51baf7ec67b1867e79`.
- Section-map evidence still passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ... mapped_entry_rows=1`.
- The crash from `history/26` is fixed: no pre-entry mutex assertion occurred.
- The new timer-opportunity marker emitted 128 pre-stream samples.
- Comparator result:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=fail divergence=missing-first-watch-read`.
- Browser pre-stream opportunity fields:
  `browser_pre_stream_timer_opportunities=128`,
  `browser_pre_stream_timer_opportunity_ready=0`,
  `browser_pre_stream_timer_opportunity_expired=128`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`.
- First browser pre-stream opportunity:
  `line=1271 ready=no reason=wait-not-pfifo-empty eip=0x80024307 irq=0x00000000 wait_op=vblank-suppress virtual_expired=yes watch_ticks=0`.
- Last browser pre-stream opportunity:
  `line=1455 ready=no reason=wait-not-pfifo-empty eip=0x8003158a irq=0x00000000 wait_op=vblank-suppress virtual_expired=yes watch_ticks=0`.
- Browser still had no pre-stream PIT, main-loop timer progress, PIC ack `0x30`,
  vector `0x30` service, or IRET before the first stream-idle transition.
- Browser reached only one post-stream vector `0x30` service in this artifact,
  and `scripts/xbox-iret-frame-compare.py` failed with
  `reason=browser-missing-iret-pair`.
- The focused marker is heavier than the prior front-most run: it did not reach
  the first watched read before the 90s boot timeout, so this artifact explains
  the pre-stream pump gate but does not replace the ready-edge-host4 baseline as
  the best full CPU-flow artifact.
- B6 still does not pass. The dashboard checker failed on this non-combined
  diagnostic log with `reason=missing-xbe-read-complete-marker`.

## Decision

- Status: diagnostic support
- Why: this proves safe entry-ready browser timer opportunities exist before
  stream-idle, but all sampled opportunities are blocked by
  `wait-not-pfifo-empty` while virtual timers are expired and watched ticks stay
  zero. It also shows the full 128-sample marker is too heavy to preserve the
  first watched read and IRET-pair evidence in the same 90s probe.

## Next Step

- Run the required post-history sub-agent loop check.
- The likely next bounded action is to reduce perturbation while keeping the new
  fact: rerun once with a much smaller `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT`
  or summarize-only timer-opportunity marker so the artifact can preserve the
  first watched read while still reporting whether opportunities remain blocked
  by `wait-not-pfifo-empty`.
