# Edge Decision Skip Marker Runtime

## Purpose

- One new fact this run was supposed to produce: `edge_trace_marker_absence_reason`, meaning whether target-PC hits are absent, skipped by cheap gates, skipped by stream/PFIFO state, or reaching the heavier `edge-decision` path.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1

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
XEMU_BROWSER_RUNTIME_PORT=8836 \
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
  > build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log \
  2>&1

rg -n "edge-decision" build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
rg -n "BROWSER_RUNTIME_SMOKE|dashboard=xbe-loaded|dashboard=xbe-entry-probe|dashboard=xbe-executed|dashboard=xbe-read|missing-xbe-executed-marker|pfifo=stream-idle|memory-watch context=browser-runtime|main-loop=timers context=browser-runtime" build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' --log build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log --out build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1-combined.log --require-context browser-runtime
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log skip=build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-skip-v1-combined.log`
- Fixture assumptions: ready-edge host4 baseline knobs, deterministic scheduling omitted, `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4`, patched WASM artifact from `history/86`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `edge_trace_marker_absence_reason`.

## Findings

- Result: `edge_trace_marker_absence_reason=stream-idle-gate-false`.
- Two target-PC hits emitted `BOOT_MARK b6 edge-decision-skip`:
  - line 2653: `reason=stream-idle-gate-false guest_pc=0x80030e84 tb_size=111 loaded=yes entry_ready=yes executed=no wait_source=pcrtc wait_op=vblank-suppress stream_idle=no wait_pfifo_known=no`.
  - line 2655: same reason and wait state for the second hit.
- No heavy `BOOT_MARK b6 edge-decision` marker emitted, which is now explained: the target PC was reached, but the stream-idle gate was false at the pre-TB hook.
- The memory-watch callbacks at `eip=0x80030e84` also reported `stream_idle=no nv2a_wait_source=pcrtc nv2a_wait_op=vblank-suppress`, with values `0x00000000` then `0x00002710`.
- Earlier focused edge context still had PFIFO stream-idle state:
  - `main-loop=timers ... source=browser-headless-host-pump-bounded ... eip=0x80014f1c ... stream_idle=yes nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty`.
  - `main-loop=timers ... source=browser-headless-host-pump-bounded ... eip=0x80014f32 ... stream_idle=yes nv2a_wait_source=pfifo-window nv2a_wait_op=pusher-empty`.
- `BROWSER_RUNTIME_EVIDENCE result=pass`.
- `DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=502adc04b73acf6c8533d771e6bea6131b45aa1db6bad0f9ac3a0f2e0820f881`.
- `DASHBOARD_SECTION_MAP_EVIDENCE result=pass`.
- `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass`.
- `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-first-watch-read`; browser has a watched write at `0x80030e84` with 0 ticks but no focused watched read.
- `POST_SERVICE_EDGE_DECISION_COMPARE result=pass ... classifications=baseline:useful-post-service-edge,skip:watch-write-without-focused-read ... top_edges=baseline:0x80030e84->0x80030f31,skip:0x80030e4c->0x80014f10`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map/stream-idle were preserved. Strict dashboard execution remained missing. Focused post-service read/edge and IRET evidence were missing in this run.

## Decision

- Status: current
- Why: the new marker answered the immediate absence question. The target PC is reached, but the edge-decision capture is gated out because the latest wait snapshot has moved to `pcrtc/vblank-suppress`, not PFIFO stream-idle.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check. The likely next technical move is to stop treating the latest global NV2A wait snapshot as the edge-decision stream-idle truth at `0x80030e84`; inspect whether the hook should use the most recent PFIFO stream-idle boundary/sequence or record both current wait and last PFIFO-idle wait without allowing PCRTC suppression to erase the PFIFO-idle context.
