# 134. Pre-first-read TCG v2 same-origin runtime

## Purpose

Run one controlled browser runtime with the rebuilt wasm while restoring the known v1 browser origin/port, to distinguish the v2 early timeout from a source/build regression.

## Loop-Guard Field

- `same_origin_v2_reaches_b6_boundary`

## Exact Commands

```sh
mkdir -p build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin
```

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
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log \
  2>&1
```

```sh
wc -l build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

rg -n "BROWSER_ASSET_AUTO|BROWSER_BLOCK_BACKING|BROWSER_RUNTIME_TRANSCRIPT|BROWSER_RUNTIME_SMOKE|DASHBOARD_|dashboard=xbe-read|dashboard=xbe-load|entry-ready|section-map|pfifo=stream-idle|tcg=timer-pump|memory-watch|tick-block|edge-decision|display_capture|BROWSER_DISPLAY_CAPTURE|BROWSER_DISPLAY_SCANOUT" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

rg -n "bmdma|ide_dma|ide=hdd|first_read_lba|BOOT_MARK b[0-6]|nv2a-pfifo started|placeholder" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

rg -n "dashboard=xbe-executed|DASHBOARD_LOADED_EVIDENCE|NATIVE_DASHBOARD_REFERENCE|missing-xbe-executed-marker|xbe-executed" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

rg -n "main-loop=timers|headless=timer-pump-step|cpu=hard-irq-service|cpu=iret|pic=irq-ack|kernel-loop-probe|tick-block=complete|tcg=timer-pump|edge-decision" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log
```

```sh
scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log
```

```sh
scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log \
  --out build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log
```

## Inputs and Artifacts

- Runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log`
- Native reference:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Rebuilt wasm:
  `build-wasm-pic/qemu-system-i386.wasm`

## Findings

- The same-origin runtime exited normally from the smoke wrapper with `boot_result=timeout`, and the transcript has 2707 lines.
- Restoring port `8846` restored the useful boundary:
  - B3/B5 browser runtime evidence passes.
  - B4 display capture evidence passes with browser-framebuffer hash `0de9130531cd3bbbde6f20f505176737182b8caa57a4795546f65d40c9552a9f`.
  - Dashboard read progress, `dashboard=xbe-loaded`, section-map, entry-ready section details, detector proof, PFIFO stream-idle, IRQ service, IRET, memory-watch, and tick-block markers all appear.
  - The read-evidence combiner passes and appends `dashboard=xbe-read`.
- Strict B6 still fails on the combined log:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- The opt-in TCG pump did fire:
  `BOOT_MARK b6 tcg=timer-pump ... mode=pit-post-pfifo-pre-first-read ... eip=0x80030e84 ... timer_progress=yes`.
- The pre-service tick-gap comparator still reports:
  `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup`.
- The first browser observed shared-word read remains at 0 ticks:
  `browser_first_watch_read_ticks=0`,
  while native remains at 136 ticks.
- The TCG pump fires after the first observed shared-word read line and before the watched write/tick-block completion. It therefore does not move the primary metric.
- The post-service watch-edge comparator regresses for this artifact:
  `POST_SERVICE_WATCH_EDGE_COMPARE result=fail divergence=missing-browser-post-edge`.
- The edge-decision marker after the TCG pump is skipped with:
  `reason=stream-idle-gate-false`,
  because the current wait snapshot has become `wait_source=pcrtc wait_op=vblank-suppress`, even though the prior PFIFO idle snapshot is present.

## Decision

`same_origin_v2_reaches_b6_boundary=yes`

The early v2 timeout was harness/origin drift, not evidence against the code change. The predicate change is now tested and is negative for the primary metric: it fires too late or in the wrong wait-snapshot state to make the first browser shared-word read catch up toward native.

## Next Step

Run the required bounded sub-agent loop check before any further code change or runtime. Ask it to critique whether the next fact should be a static ordering audit of the TCG pump call site and wait-snapshot source change around lines 2650-2670, rather than another runtime.
