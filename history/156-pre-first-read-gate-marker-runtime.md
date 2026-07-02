# Pre-First-Read Gate Marker Runtime

## Purpose

- One new fact this run was supposed to produce: `scheduler_not_armed_reason`, using the new bounded `scheduler=pre-first-read-gate` marker before the first watched read.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pre-first-read-gate-marker-v1

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
XEMU_BROWSER_RUNTIME_PORT=8847 \
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
  > build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime-combined.log \
  --require-context browser-runtime
scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime-combined.log
rg -n 'scheduler=pre-first-read-gate|scheduler=pre-first-read|tcg=timer-pump|memory-watch|tick-block=complete|edge-decision|pfifo=stream-idle|main-loop=timers|headless=timer-pump-step' \
  build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log`
- Combined output log: `build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime-combined.log`
- Fixture assumptions: real browser runtime with Firefox BiDi, rebuilt wasm in `build-wasm-pic`, PCRTC vblank off, ready-edge host pump still capped at 4 progress events, memory watch on physical `0x0003a890` write access.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `scheduler_not_armed_reason`.

## Findings

- Result: negative evidence; the marker emitted too early and consumed its budget before the close window.
- `BROWSER_RUNTIME_EVIDENCE result=pass`.
- `DISPLAY_CAPTURE_EVIDENCE result=pass` with framebuffer hash `c0a4ff659877bbf1f7e00fd1d77f7b4d6ad85c51ebdfade93df3156da529a727`.
- Raw dashboard loaded check failed before combining due to `missing-xbe-read-complete-marker`; the combiner produced the combined log successfully.
- Combined strict B6 check still failed: `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- `scheduler=pre-first-read-gate` emitted 64 markers, all with `reason=entry-not-ready`, `entry_ready=no`, `loaded=yes`, `virtual_has_timers=yes`, `virtual_expired=yes`, and `watch_ticks=0`.
- First gate marker: line 1036, `eip=0x8002430e`, `cpu_interrupt_request=0x00000002`, `wait_source=pcrtc`, `wait_op=vblank-suppress`.
- Last gate marker: line 1101, still `reason=entry-not-ready`, `entry_ready=no`, `loaded=yes`, `eip=0x80014386`.
- `dashboard=xbe-section-map phase=entry-ready` appears later at line 1208.
- `memory-watch-install result=pass ... source=entry-ready` appears later at line 1216.
- No `scheduler=pre-first-read` marker appeared.
- No `tcg=timer-pump` marker appeared.
- `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-stream-idle-transition`.
- `POST_SERVICE_WATCH_EDGE_COMPARE result=fail divergence=missing-browser-pre-edge,browser-post-edge`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map did not regress. PFIFO stream-idle, pre-service tick-gap comparability, and the useful post-service watch edge regressed or were not observed in this artifact.

## Decision

- Status: negative evidence
- Why: the run did not answer the close-window `scheduler_not_armed_reason`. It instead proved the marker emission filter is wrong: logging starts at `loaded=yes` while `entry_ready=no`, burns the 64-line budget, and never reaches the intended entry-ready/pre-first-read window. The artifact should not replace the `history/152` boundary baseline.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/155` approved exactly one runtime validation, judged first on the earliest gate marker. The earliest marker now shows the diagnostic itself is too early.

## Next Step

- Narrow follow-up: run the required loop check. The likely revision is to gate `scheduler=pre-first-read-gate` emission on `entry_ready=yes`, not `loaded=yes`, and to avoid watch-word reads before entry-ready.
