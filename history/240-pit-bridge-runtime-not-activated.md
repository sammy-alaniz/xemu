# PIT Bridge Runtime Not Activated

## Purpose

- One new fact this run was supposed to produce: `pit_attributed_pre_stream_bridge_preserves_post_service_edge`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1

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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE=1 \
XEMU_BROWSER_BOOT_PIT_PRE_STREAM_BRIDGE_LIMIT=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
scripts/xbox-combine-dashboard-xbe-read-evidence.sh --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' --log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log --out build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log --require-context browser-runtime
rg -n "main-loop=timers .*source=browser-pit-prestream-bridge|source=browser-ready-edge-qemu-pump|source=browser-headless-host-pump-bounded|pfifo=stream-idle-transition|pfifo=stream-idle-boundary|cpu=hard-irq-service|cpu=iret|memory-watch" build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
scripts/xbox-post-service-watch-edge-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log
scripts/xbox-b6-current-boundary.sh --browser-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log --timer-opportunity-log build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
rg -n "browser-pit-prestream-bridge|pit-prestream|headless=timer-opportunity|headless=timer-pump-gate|main-loop=timers|pic=irq-ack|cpu=hard-irq-service|cpu=iret|dashboard=xbe-executed" build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Runtime log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1/browser-runtime.log`
- Combined browser log: `build-real-b3-matrix/browser-pit-prestream-bridge-limit1-v1-combined.log`
- Fixture assumptions: new bridge requested through environment variables; no fixture-file plumbing was added for the new setting.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pit_attributed_pre_stream_bridge_preserves_post_service_edge`

## Findings

- Result: `pit_attributed_pre_stream_bridge_preserves_post_service_edge=fail`.
- The runtime exited successfully and timed out as expected:
  `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`.
- Display evidence passed:
  `DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=67e25d5486ab878d031d4bc1e28828f35314b5a4501fa8ea470028d2ede8b54f`.
- Section-map evidence passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... executable_sections=1 ... entry_section=3`.
- Dashboard read combination passed:
  `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass`.
- Strict B6 still failed:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- The bridge did not activate:
  - no `main-loop=timers source=browser-pit-prestream-bridge`,
  - no `pit-prestream` marker,
  - first browser timer source remained `browser-ready-edge-qemu-pump`.
- The pre-stream opportunities still showed expired timers blocked by PFIFO readiness:
  `headless=timer-opportunity ... ready=no reason=wait-not-pfifo-empty ... virtual_expired=yes`.
- Preservation failed before tick movement could be interpreted:
  - `PRE_SERVICE_TICK_GAP_COMPARE result=fail divergence=missing-first-watch-read`,
  - `POST_SERVICE_WATCH_EDGE_COMPARE result=fail divergence=missing-browser-pre-edge,browser-post-edge`,
  - `IRET_FRAME_COMPARE result=fail reason=browser-missing-hard-irq-service-after`.
- Focused boundary details:
  - browser first watched read: none,
  - browser first watched write: `eip=0x80030e84 value=0x00000000`,
  - browser post-service top edge: `0x8001b02f->0x8001b030`,
  - browser pre-stream timer progress: 0,
  - browser pre-stream vector `0x30` service: 0,
  - browser pre-stream IRET after: 0.
- Current boundary helper result:
  `B6_CURRENT_BOUNDARY_RESULT result=fail reason=required-diagnostic-failed ... next=restore-browser-main-loop-timer-progress`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  B4/B5/read/load/entry-ready/section-map/stream-idle passed. Vector `0x30` service/IRET, first watched read, and post-service edge regressed or were missing relative to the stable ready-edge host4 baseline.

## Decision

- Status: negative evidence
- Why: the approved runtime did not activate the new bridge and did not preserve the post-service edge. Tick movement is not interpretable because the bridge source marker is absent and preservation failed.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/239-pit-bridge-runtime-loop-check.md` approved exactly one runtime and required branch-exit if the bridge did not activate or preservation regressed. No limit tuning or second bridge runtime is allowed from this result alone.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique. The next decision must be either quarantine the bridge, or treat this as a setup/plumbing failure only if the loop check approves a static fixture/env-plumbing inspection before any further runtime.
