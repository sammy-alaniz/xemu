# Edge Decision Ready-Edge Runtime

## Purpose

- One new fact this run was supposed to produce: whether `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` can run on the known ready-edge host4 browser baseline without deterministic scheduling and either emit `BOOT_MARK b6 edge-decision` markers or preserve the useful post-service edge.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1

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
XEMU_BROWSER_RUNTIME_PORT=8835 \
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
  > build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log \
  2>&1

rg -n "edge-decision" build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
rg -n "BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_EVIDENCE|DISPLAY_CAPTURE_EVIDENCE|DASHBOARD_SECTION_MAP_EVIDENCE|DASHBOARD_LOADED_EVIDENCE|missing-xbe-executed-marker|dashboard=xbe-executed|dashboard=xbe-read|dashboard=xbe-loaded|dashboard=xbe-entry-probe" build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
rg -n "BOOT_MARK b6 dashboard=kernel-loop-probe .*0x80030e84|BOOT_MARK b6 memory-watch|BOOT_MARK b6 main-loop=timers|BOOT_MARK b6 pfifo=stream-idle|BOOT_MARK b6 pic=service|BOOT_MARK b6 cpu=iret" build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' --log build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log --out build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1-combined.log --require-context browser-runtime
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log edge_trace=build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1/browser-runtime.log`
- Combined log: `build-real-b3-matrix/browser-main-menu-edge-decision-readyedge-v1-combined.log`
- Fixture assumptions: ready-edge host4 baseline knobs, edge-decision limit 4, deterministic scheduling omitted.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `POST_SERVICE_EDGE_DECISION_COMPARE classifications=edge_trace:<missing-stream-idle-boundary|useful-post-service-edge|watch-write-without-focused-read>` and `browser_post_service_top_edge`.

## Findings

- Result: browser runtime reached the useful B4/B5/dashboard-read side of the baseline but did not emit edge-decision markers and did not preserve the useful focused post-service edge.
- No `BOOT_MARK b6 edge-decision` marker was found.
- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- `DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=fe32e59933b73c4a21ef7f2c0808a653494650e3dde40953738ed5f77e7bfca2`.
- `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... executable_sections=1 ... entry_section=3`.
- `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass`.
- `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- Runtime read/load/entry-ready evidence was present, including `dashboard=xbe-loaded` and `dashboard=xbe-entry-probe ... status=ready`.
- `dashboard=xbe-executed-detector-proof ... result=pass reason=accepted subject=entry ... source=entry-ready` was present, but the strict runtime execution marker was still absent.
- `pfifo=stream-idle-transition` and `pfifo=stream-idle-boundary` were present.
- The first watched write was present at `eip=0x80030e84` with `value=0x00000000`.
- `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-first-watch-read`: browser had a watched write at `0x80030e84` but no focused watched read.
- `POST_SERVICE_EDGE_DECISION_COMPARE result=pass ... classifications=baseline:useful-post-service-edge,edge_trace:watch-write-without-focused-read ... top_edges=baseline:0x80030e84->0x80030f31,edge_trace:0x8001b030->0x8001b02f`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4/B5/read/load/entry-ready/section-map/stream-idle were preserved. The focused post-service read/edge and IRET evidence regressed relative to the ready-edge host4 baseline.

## Decision

- Status: negative evidence
- Why: isolating edge-decision tracing from deterministic scheduling reached the baseline enough to show the trace mode is still too perturbing or too narrowly gated; it did not produce the intended `edge-decision` marker and shifted the observed post-service flow to `watch-write-without-focused-read`.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check with an added progress-method critique. The likely technical revision is to inspect the edge-decision hook/gating for perturbation before another runtime: the next field should explain why edge tracing with a nonzero limit changes the post-service path or why the marker gate never sees `0x80030e84` under stream-idle.
