# Edge Decision Last PFIFO Idle Runtime

## Purpose

- One new fact this run was supposed to produce: whether the target-PC edge decision sees current PFIFO stream-idle state, retained last-PFIFO-idle state, or only a non-PFIFO latest wait snapshot at `0x80030e84`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1

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
XEMU_BROWSER_RUNTIME_PORT=8837 \
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
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log \
  2>&1

rg -n "edge-decision" build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
rg -n "pfifo=stream-idle|main-loop=timers context=browser-runtime|memory-watch context=browser-runtime|BROWSER_RUNTIME_SMOKE|dashboard=xbe-executed|dashboard=xbe-loaded|dashboard=xbe-entry-probe" build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' --log build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log --out build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1-combined.log --require-context browser-runtime
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log last_pfifo=build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1-combined.log`
- Fixture assumptions: ready-edge host4 baseline knobs, deterministic scheduling omitted, `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, patched WASM artifact from `history/90`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `edge_decision_current_vs_last_pfifo_idle_context` and `edge_decision_last_pfifo_idle_present_at_target_pc`.

## Findings

- Result: the heavy `edge-decision` marker emitted; the skip path was not needed.
- `BOOT_MARK b6 edge-decision` at line 2643 captured `start_pc=0x80030e84 next_pc=0x80030f31 tb_size=111 tb_exit=0`.
- The edge decision saw current PFIFO stream-idle state directly: `pre_stream_idle=yes pre_wait_source=pfifo-window pre_wait_op=pusher-empty pre_wait_seq=379 pre_wait_dma_get=0x03881318 pre_wait_dma_put=0x03881318`.
- At the same edge, the watched word was still behind native: `pre_watch_value=0x00000000`, `start_mem_addr=0x8003a890`, `start_mem_phys=0x0003a890`, `start_mem_value=0x00000000`.
- The block itself advanced the watched word by one tick: the next kernel-loop probe after the block shows `start_mem_value=0x00002710`, and later `main-loop=timers` sampled `memory_watch_value=0x00002710`.
- The local post-service block is therefore structurally sound in browser for this run; the unresolved gap is pre-block tick accumulation.
- `BROWSER_RUNTIME_EVIDENCE result=pass`.
- `DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=7781fa89f8722deb60c0268c89488da521d35cce682848e078d59baa39c53a81`.
- `DASHBOARD_SECTION_MAP_EVIDENCE result=pass`.
- `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass`.
- `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup ... native_first_watch_read_ticks=136 ... browser_first_watch_read_ticks=0 ... browser_first_watch_read_edge=0x80014f32->0x80030e84`.
- `POST_SERVICE_EDGE_DECISION_COMPARE result=pass ... classifications=baseline:useful-post-service-edge,last_pfifo:missing-focused-watch-read ... top_edges=baseline:0x80030e84->0x80030f31,last_pfifo:0x80030e4c->0x80030f31`. The comparator missed the explicit edge-decision marker because it keys on post-IRET focus windows, but the raw runtime marker captured the exact desired `0x80030e84 -> 0x80030f31` TB.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map/stream-idle/IRET were preserved. Strict dashboard execution remains missing.

## Decision

- Status: current
- Why: the last marker/schema iteration answered the current-vs-last-PFIFO question. Current PFIFO stream-idle is available at the target edge in this run, and the useful block executes. The remaining blocker is not PC reachability or wait-snapshot volatility; it is the 136-tick pre-block deficit.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check. Per the process constraint, do not add more edge-decision schema. Move to a behavioral/deterministic ordering change that accumulates timer ticks before `0x80014f32->0x80030e84`, or explicitly return to deterministic PFIFO/PCRTC/timer ordering with `browser_first_watch_read_ticks` as the field.
