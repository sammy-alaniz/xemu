# Ready-Edge All-Timers Negative Evidence

## Purpose

- One new fact this run was supposed to produce: whether replacing the ready-edge virtual-only one-timer pump with native-like `qemu_clock_run_all_timers()` moves `pre_service_browser_first_watch_read_ticks` away from `0` toward native `136`.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

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
XEMU_BROWSER_RUNTIME_PORT=8823 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump-all \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log \
  2>&1

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log

PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

git diff --check
scripts/xbox-pre-service-tick-gap-compare-selftest.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-all-v2/browser-runtime.log`
- Fixture assumptions: local real B6 fixtures from `goal.md`; fixture preflight passed in the runtime smoke.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_service_browser_first_watch_read_ticks`, `browser_post_service_top_edge`, and `browser_xbe_executed`.

## Findings

- Result: browser runtime smoke passed, B4 display capture passed, and section-map evidence passed, but this is negative evidence for B6.
- The wasm rebuild succeeded after fixing the `source` variable scope in `hw/xbox/nv2a/pfifo.c`.
- The run applied `browser_headless_timer_pump_mode=pfifo-ready-edge-qemu-pump-all` and emitted `main-loop=timers source=browser-ready-edge-qemu-pump-all`.
- The all-timers ready-edge pump advanced virtual time much more than the current baseline: `browser_first_timer_virtual_advance_ns=130299904`, but the watched value at that timer sample was still `0x00000000`.
- `PRE_SERVICE_TICK_GAP_COMPARE` regressed from the current baseline to `result=fail divergence=missing-first-watch-read`; no browser first watched read was observed after PFIFO stream-idle.
- The boundary helper reports `browser_post_service_top_edge=0x8001b02f->0x8001b030`, `iret=fail`, `post_service_watch_edge=fail`, `post_idle_timer_divergence=browser-missing-main-loop-timer-progress`, and `next=restore-browser-main-loop-timer-progress`.
- The strict B6 checker still fails, here at `missing-xbe-read-complete-marker` on the raw runtime log; no browser-runtime `dashboard=xbe-executed` marker appears.
- I also added `stream_idle=` to `main-loop=timers` markers and rebuilt wasm again so future logs can classify timer markers without inferring from surrounding wait fields.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4, B5, dashboard load/entry-ready, and section-map stayed present. The useful browser IRET/post-service flow regressed, so this artifact must remain negative evidence.

## Decision

- Status: negative evidence
- Why: native-like all-timers dispatch at the ready edge does not move the first watched read toward native; it instead loses the useful service/IRET/post-service path while leaving the watched word at zero.
- Independent critique used: no

## Next Step

- Narrow follow-up: do not promote all-timers ready-edge pumping. Return to the current ready-edge plus host-fallback baseline and inspect why the virtual-only ready-edge timer event sets `cpu_interrupt_request=0x00000002` before the first service but still reaches the first watched read before the watched word has accumulated native-like ticks.
