# Call Chain Browser Runtime

## Purpose

- One new fact this run was supposed to produce:
  whether browser runtime emits the env-gated broad `CALL_CHAIN` markers after
  the flag is delivered through browser trace options into
  `/xemu-fixtures/call_chain_trace.txt`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-call-chain-trace-v1

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
XEMU_BROWSER_RUNTIME_PORT=8831 \
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
XEMU_BOOT_TRACE_CALL_CHAIN=1 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log \
  2>&1

rg -n '^CALL_CHAIN' \
  build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-call-chain-trace-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-call-chain-trace-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-call-chain-trace-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser runtime log:
  `build-real-b3-matrix/browser-call-chain-trace-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-call-chain-trace-v1-combined.log`
- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions:
  real MCPX, flash, EEPROM, and HDD paths from `AGENTS.md` were used locally.

## Expected Field(s)

- Loop-guard field this run could explain:
  `browser_xbe_executed`, through the diagnostic subfact
  `browser_call_chain_reaches_mark_executed_attempt`.

## Findings

- Result:
  browser runtime does emit the `CALL_CHAIN` markers.
- Flag delivery was confirmed:
  - `BROWSER_DIAGNOSTIC name=call_chain_trace value=1`
  - `BROWSER_DIAGNOSTIC_APPLY name=call_chain_trace value=1 target=/xemu-fixtures/call_chain_trace.txt`
  - `BROWSER_RUNTIME_TRANSCRIPT ... trace_call_chain=1`
- Important call-chain lines:
  - `CALL_CHAIN started main!`
  - `CALL_CHAIN started qemu_main_thread!`
  - `CALL_CHAIN started qemu_init!`
  - `CALL_CHAIN started qemu_init_board!`
  - `CALL_CHAIN started machine/device/CPU setup!`
  - `CALL_CHAIN started qemu_main_loop!`
  - `CALL_CHAIN started TCG vCPU execution loop!`
  - `CALL_CHAIN started tcg_cpu_exec!`
  - `CALL_CHAIN started cpu_exec!`
  - `CALL_CHAIN started cpu_exec_loop!`
  - `CALL_CHAIN started cpu_loop_exec_tb!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_observe_exec!`
  - `CALL_CHAIN ended xemu_xbe_boot_trace_observe_exec!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_mark_executed!`
  - `CALL_CHAIN ended xemu_xbe_boot_trace_mark_executed!`
- The browser reached `xemu_xbe_boot_trace_mark_executed()`, but the first
  attempt rejected through:
  `BOOT_MARK b6 dashboard=xbe-exec-section-miss context=browser-runtime reason=high-alias-phys-mismatch entry_ready=no ...`.
- Browser later emitted detector proof:
  `BOOT_MARK b6 dashboard=xbe-executed-detector-proof context=browser-runtime result=pass ... source=entry-ready`.
- Browser did not emit strict:
  `BOOT_MARK b6 dashboard=xbe-executed`.
- Evidence checks:
  - `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`
  - `DISPLAY_CAPTURE_EVIDENCE result=pass ...`
  - `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ...`
  - `COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass ... context=browser-runtime`
  - `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`
- Boundary result stayed B6-fail:
  `B6_CURRENT_BOUNDARY_RESULT result=fail reason=required-diagnostic-failed b6=fail b6_reason=missing-xbe-executed-marker native_xbe_executed=yes browser_xbe_executed=no`.
- The pre-service metric did not improve:
  `pre_service_browser_first_watch_read_ticks=0`,
  `pre_service_native_first_watch_read_ticks=136`,
  `pre_service_first_watch_read_tick_delta=136`.

## Decision

- Status: historical support
- Why:
  this answers the user's call-chain question for browser runtime. The markers
  do pop up, including the `mark_executed()` entry and exit markers, but this is
  not B6 completion evidence because strict browser `dashboard=xbe-executed`
  remains missing.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/61-call-chain-browser-runtime-pre-run-loop-check.md` approved this
  browser run only to explain `browser_xbe_executed` via
  `browser_call_chain_reaches_mark_executed_attempt`.

## Next Step

- Narrow follow-up:
  return to the B6 causal boundary. The call-chain experiment explains that the
  browser reaches the marker decision path and rejects an early candidate; the
  primary unresolved B6 metric is still browser tick accumulation before the
  first watched read, with browser at 0 ticks versus native at 136.
