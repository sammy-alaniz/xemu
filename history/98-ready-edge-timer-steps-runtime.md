# Ready Edge Timer Steps Runtime

## Purpose

- One new fact this run was supposed to produce: whether a non-deterministic ready-edge host pump using `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2` moves `browser_first_watch_read_ticks` above `0`.

## Command(s)

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
XEMU_BROWSER_RUNTIME_PORT=8838 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log steps2=build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-main-menu-readyedge-steps2-v1-combined.log`
- Fixture assumptions: real MCPX, flash, EEPROM, HDD fixtures; browser runtime uses Firefox BiDi and rebuilt `build-wasm-pic` artifacts.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `browser_first_watch_read_ticks`.

## Findings

- Result: runtime command exited `0`; browser runtime evidence passed, but the boot result was still `timeout`.
- The new timer-step path did run: `headless=timer-pump-step-count context=browser-runtime deterministic=no step_limit=2` appears in the runtime log.
- The strict B6 gate still failed as expected: `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- The target field did not move: `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup`, with `native_first_watch_read_ticks=136` and `browser_first_watch_read_ticks=0`.
- The first browser watched read remained on `browser_first_watch_read_edge=0x80014f32->0x80030e84`, and the first watched write followed it rather than preceding it.
- Extra browser `main-loop=timers` markers occurred before the first watched read, but their memory-watch samples still read `0x00000000`.
- The post-service edge decision regressed as a shape signal: `POST_SERVICE_EDGE_DECISION_COMPARE result=pass` classified `baseline:useful-post-service-edge` and `steps2:post-service-edge-diverged`, with top edges `baseline:0x80030e84->0x80030f31` and `steps2:0x80030e4c->0x80030e84`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map/stream-idle/IRQ/IRET evidence remained present, but the useful post-service edge shape regressed.

## Decision

- Status: negative evidence
- Why: `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2` was applied, but it did not move `browser_first_watch_read_ticks`; increasing this count blindly would repeat the same hypothesis after the relevant field failed to improve.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history/97 approved exactly one steps=2 runtime and said to stop increasing step count blindly if the field stayed at `0`.

## Progress-Method Critique

- This run improved the method because it tested one named field instead of re-confirming `missing-xbe-executed-marker`.
- The result weakens the "not enough ready-edge timer callbacks" hypothesis: extra callbacks happened before the first watched read, but the watched word stayed at `0`.
- The result suggests the next method should inspect the producer/timer routing for physical `0x0003a890` and the ordering of the relevant write, not run steps=3 or another broad pump-placement variant.
- The post-service edge regression means steps=2 should not become the active baseline.

## Next Step

- Narrow follow-up: run a bounded loop-check with progress-method critique, then likely inspect the code path that produces or schedules writes to physical `0x0003a890` before adding another runtime.
