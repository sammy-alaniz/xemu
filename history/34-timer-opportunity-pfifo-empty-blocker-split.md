# Timer Opportunity PFIFO Empty Blocker Split

## Purpose

- One new fact this run was supposed to produce: which exact PFIFO-empty
  subpredicate makes expired pre-stream browser timer opportunities report
  `reason=wait-not-pfifo-empty`.

## Command(s)

```sh
python3 -m py_compile scripts/xbox-pre-stream-tick-source-compare.py
bash -n scripts/xbox-pre-stream-tick-source-compare-selftest.sh \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-b6-current-boundary.sh
scripts/xbox-pre-stream-tick-source-compare-selftest.sh
node --check browser/xbox-boot/worker.js
node --check browser/xbox-boot/main.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
git diff --check -- \
  AGENTS.md \
  goal.md \
  xemu-xbe.c \
  scripts/xbox-pre-stream-tick-source-compare.py \
  scripts/xbox-pre-stream-tick-source-compare-selftest.sh \
  browser/xbox-boot/worker.js \
  browser/xbox-boot/main.js \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  scripts/xbox-browser-runtime-smoke.sh \
  history/32-timer-opportunity-limit8-plumbed.md \
  history/33-timer-opportunity-gate-split-loop-check.md

PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1

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
XEMU_BROWSER_RUNTIME_PORT=8828 \
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
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log \
  2>&1

rg -n "BROWSER_DIAGNOSTIC name=xbe_timer_opportunity_limit|BROWSER_DIAGNOSTIC_APPLY name=xbe_timer_opportunity_limit|headless=timer-opportunity|pfifo_empty_blocker|BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_TRANSCRIPT" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-iret-frame-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
```

## Inputs And Artifacts

- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- Native comparator baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- C marker change: `xemu-xbe.c` now emits
  `pfifo_empty_blocker=<blocker>` on `headless=timer-opportunity`.
- Comparator change: `scripts/xbox-pre-stream-tick-source-compare.py` now
  reports blocker sets plus first/last opportunity wait source and blocker.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by explaining why expired
  pre-stream browser timer work does not dispatch before the first watched read.
- `browser_pre_stream_timer_opportunity_pfifo_empty_blockers`, as the new split
  field that names the failed PFIFO-empty predicate.

## Findings

- Static JS/shell/Python checks passed.
- The pre-stream comparator selftest passed all 3 cases.
- The wasm rebuild passed and linked `qemu-system-i386.js`.
- Setup evidence is present:
  `BROWSER_DIAGNOSTIC name=xbe_timer_opportunity_limit value=8`,
  `BROWSER_DIAGNOSTIC_APPLY name=xbe_timer_opportunity_limit value=8 target=/xemu-fixtures/xbe_timer_opportunity_limit.txt`,
  and runtime summary `trace_xbe_timer_opportunity_limit=8`.
- B5 runtime evidence passed:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- B4 display capture passed with hash
  `d134b59ec9112910e1485834d6f6e0ee3ac9ceac987a657bc39b3964cfd3bb82`.
- Section-map evidence passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... phase=entry-ready ... mapped_entry_rows=1`.
- Pre-stream comparator passed diagnostically:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=pass divergence=browser-lacks-pre-stream-vector-service`.
- The new blocker split is decisive:
  `browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window`.
- Browser pre-stream opportunity fields:
  `browser_pre_stream_timer_opportunities=8`,
  `browser_pre_stream_timer_opportunity_ready=0`,
  `browser_pre_stream_timer_opportunity_expired=8`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`.
- First opportunity:
  `line=1162 ready=no reason=wait-not-pfifo-empty eip=0x8002430e irq=0x00000000 wait_source=pcrtc wait_op=vblank-suppress pfifo_empty_blocker=wait-source-not-pfifo-window virtual_expired=yes watch_ticks=0`.
- Last opportunity:
  `line=1228 ready=no reason=wait-not-pfifo-empty eip=0x80014386 irq=0x00000000 wait_source=pcrtc wait_op=vblank-suppress pfifo_empty_blocker=wait-source-not-pfifo-window virtual_expired=yes watch_ticks=0`.
- Browser first watched read is preserved:
  `browser_first_watch_read_line=2515`,
  `browser_first_watch_read_edge=0x80014f32->0x80030e84`,
  `browser_first_watch_read_value=0x00000000`,
  `browser_first_watch_read_ticks=0`.
- Native first watched read remains `136`; the delta is still
  `first_watch_read_tick_delta=136`.
- Browser still has zero pre-stream PIT rising, main-loop timer progress, PIC
  ack `0x30`, vector `0x30` service, and IRET before PFIFO stream-idle.
- Browser post-stream vector `0x30` service remains present:
  `browser_post_stream_service30=2`.
- IRET comparator passed structurally but still reports
  `divergence=interrupt-return-target-mismatch` against the native
  graphic-update baseline.
- B6 still does not pass. The dashboard checker failed on this non-combined
  diagnostic log with `reason=missing-xbe-read-complete-marker`.

## Decision

- Status: current focused gate diagnostic
- Why: the active blocker is now more precise. Expired browser virtual timer
  work exists before stream-idle, but the ready-edge pump gate is using a stale
  PCRTC wait snapshot (`wait_source=pcrtc wait_op=vblank-suppress`) rather than
  a PFIFO-window/pusher-empty snapshot, so it refuses to dispatch timers before
  the first watched read.

## Next Step

- Run the required post-history sub-agent loop check.
- If approved, update `goal.md` and `AGENTS.md` to make the gate-split v1 log
  the focused diagnostic and inspect why the timer-opportunity path sees a PCRTC
  wait snapshot while the PFIFO transition snapshot later reaches stream-idle.
