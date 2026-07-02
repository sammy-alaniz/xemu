# Tick Block Completion Marker Runtime

## Purpose

- One new fact this implementation bundle was supposed to produce: whether the
  browser completes any guest `0x80030e84->0x80030f31` watched-word tick blocks
  before PFIFO stream-idle / the first edge-decision watched read.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1

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
XEMU_BROWSER_RUNTIME_PORT=8842 \
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
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log tickblock=build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log

rg -n "tick-block=complete|trace_xbe_tick_block_limit|BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_TRANSCRIPT|DASHBOARD_LOADED_EVIDENCE|BROWSER_DISPLAY_CAPTURE|SECTION_MAP|dashboard=xbe-(read|loaded|entry-probe|executed)" \
  build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-tick-block-completion-readyedge-host4-v1-combined.log`
- Fixture assumptions: podman-backed rebuilt WASM, Firefox BiDi browser
  runtime, real MCPX/flash/HDD fixtures, diagnostic-only
  `XEMU_BOOT_TRACE_XBE_TICK_BLOCK_LIMIT=256`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, `browser_dashboard_xbe_executed`

## Findings

- Result: build passed and linked `build-wasm-pic/qemu-system-i386.js`; browser
  runtime exited `0`, but boot still ended in `browser-main-timeout`.
- The browser transcript applied the new knob:
  `trace_xbe_tick_block_limit=256`.
- Strict B6 still correctly failed:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- Browser read/load/entry-ready evidence remained present, section-map evidence
  passed, and browser display capture remained non-empty.
- The new marker emitted exactly once:
  `BOOT_MARK b6 tick-block=complete ... seq=1`.
- The new primary field is sharp:
  `pre_stream_idle_completion=no`,
  `pre_stream_idle_completions=0`, and
  `stream_idle_transition_seen=yes`.
- The first completed tick block also happened after the older edge-decision
  probe had already observed the block twice:
  `edge_decision_seen_before_completion=yes` and
  `edge_decision_count_before_completion=2`.
- The completed block itself increments the watched word normally:
  `pre_watch_value=0x00000000`, `post_watch_value=0x00002710`,
  `pre_watch_ticks=0`, `post_watch_ticks=1`, `watch_delta_ticks=1`.
- The pre-service tick-gap comparator still reports
  `native_first_watch_read_ticks=136` and
  `browser_first_watch_read_ticks=0`.
- The post-service edge comparator classified this diagnostic runtime as
  `post-service-edge-diverged` versus the active ready-edge-host4 baseline's
  `useful-post-service-edge`. Do not promote this artifact over the baseline.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  B4/B5/read/load/entry-ready/section-map/stream-idle/IRQ/IRET evidence was
  present, but the useful post-service edge shape regressed in this diagnostic
  run.

## Decision

- Status: current diagnostic evidence, not active baseline
- Why: the marker explains the boundary without satisfying B6. Browser is not
  merely missing enough host timer callbacks; it is reaching the watched read
  before any observed guest tick-block completion has happened in the
  pre-stream-idle window.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: `history/101` authorized one bounded
  code+runtime bundle and said the next marker should measure
  `pre_first_read_tick_block_completions_browser`.

## Progress-Method Critique

- This moved the method from "more timer callbacks" to a concrete guest CPU
  completion boundary.
- The marker is diagnostic-only and did not weaken the strict dashboard
  execution contract.
- The result makes the next scheduling target more deterministic: PIT/PIC timer
  delivery must be followed by guest execution through at least one completed
  `0x80030e84->0x80030f31` block before the first dashboard/post-idle watched
  read, not merely before stream-idle.
- The run also warns that the new tracing path can perturb the useful
  post-service edge shape, so future behavioral changes should be judged
  against both `pre_stream_idle_completions` and preservation of the baseline
  edge.

## Next Step

- Narrow follow-up: run the required loop-check. The likely next code step is a
  gated deterministic PIT-to-guest-execution path with an explicit stop
  condition tied to `tick-block=complete pre_stream_idle_completion=yes` or a
  small TB budget, while preserving the strict B6 detector and the useful
  post-service edge.
