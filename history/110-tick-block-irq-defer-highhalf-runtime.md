# Tick Block IRQ Defer Highhalf Runtime

## Purpose

- One new fact this run was supposed to produce: whether saving, clearing, and
  restoring `cpu->neg.icount_decr.u16.high` around the opt-in one-TB IRQ defer
  makes the first deferred `0x80030e84` TB execute instead of returning
  `tb_exit=3`.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1

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
XEMU_BROWSER_RUNTIME_PORT=8845 \
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
XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER=1 \
XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER_LIMIT=8 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log highhalf=build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

rg -n "tick-block-irq-defer" \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

rg -n "tick-block=complete|edge-decision context=browser-runtime|memory-watch context=browser-runtime" \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

rg -n "BROWSER_RUNTIME_(TRANSCRIPT|SMOKE)|DASHBOARD_LOADED_EVIDENCE|BROWSER_DISPLAY_CAPTURE" \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log`
- Fixture assumptions: podman-backed rebuilt WASM, Firefox BiDi browser
  runtime, real MCPX/flash/HDD fixtures, same ready-edge host4 shape as
  `history/106`, with only the icount high-half save/clear/restore revision
  added.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `first_deferred_tb_expected_path`,
  `tick_block_completion_before_edge_decision`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: build passed and linked `qemu-system-i386.js`; browser runtime exited
  `0`; combined evidence was written.
- The browser transcript proves the mode was applied:
  `trace_xbe_tick_block_irq_defer=1` and
  `trace_xbe_tick_block_irq_defer_limit=8`.
- Strict B6 still correctly failed:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- Section-map evidence still passed:
  `DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... executable_sections=1
  entry_section=3`.
- The intended high-half validation did not occur. The only defer marker was:
  `tick-block-irq-defer ... phase=pre action=skip reason=no-hard-irq
  start_pc=0x80030e84 ... effective_interrupt_request=0x00000000
  effective_exit_request=no sample_mismatch=no`.
- Therefore `first_deferred_tb_expected_path` is not proven; this run did not
  hit a deferred TB after the high-half patch.
- The tick block completed only after the post-service edge decision:
  `tick-block=complete ... next_pc=0x80030f31 tb_exit=0
  edge_decision_seen_before_completion=yes
  edge_decision_count_before_completion=1 pre_watch_ticks=0 post_watch_ticks=1`.
- The primary metric did not improve:
  `native_first_watch_read_ticks=136`,
  `browser_first_watch_read_ticks=0`,
  `divergence=browser-first-watch-read-before-catchup`.
- Post-service edge preservation regressed relative to the active baseline:
  baseline classification is `useful-post-service-edge`; highhalf is
  `post-service-edge-diverged`, with top edge `0x80030e4c->0x80030e84` and no
  first expected `0x80030e84->0x80030f31` block before the focus window closes.
- Browser runtime/display evidence still passed, but the smoke ended by timeout:
  `BROWSER_RUNTIME_SMOKE result=pass ... boot_result=timeout` and repeated
  `BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes` markers.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Browser runtime, display capture, read/load/entry-ready, section-map, stream
  idle, and an IRET back to `0x80030e84` remained present. Strict
  `dashboard=xbe-executed` remained missing and the useful post-service edge
  did not match the active baseline.

## Decision

- Status: negative evidence for the IRQ-defer micro-scheduler slice.
- Why: the high-half patch built, but the single approved validation did not
  exercise the defer path, did not move `browser_first_watch_read_ticks`, and
  did not preserve the active baseline's useful post-service edge.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/109` allowed exactly one validation
  judged first on `first_deferred_tb_expected_path`; because this run produced
  only `action=skip reason=no-hard-irq`, the expected-path field is unproven
  and another IRQ-defer runtime is not justified without a fresh loop check.

## Progress-Method Critique

- The metrics still connect to the final goal because strict browser
  `dashboard=xbe-executed` remains the gate before visible main-menu proof and
  game launch.
- This slice is now too diagnostic-heavy for its payoff: it has explained one
  TCG exit-request mechanism, but the runtime path no longer reaches the
  defer condition and the primary tick metric remains at 0.
- The history/loop-check process is helping by forcing this negative result to
  stop the micro-scheduler loop instead of inviting another ready-edge rerun.
- The right next mode is a required loop check, likely followed by revising
  away from one-TB IRQ deferral unless the critique identifies a non-runtime
  inspection that changes a named field.
- Process adjustment for the next 2-3 turns: do not run another
  `tick-block-irq-defer` browser validation; first decide whether to remove or
  quarantine the diagnostic patch and return to a broader deterministic
  scheduler design that can change `browser_first_watch_read_ticks`.

## Next Step

- Narrow follow-up: run the required bounded loop check with
  `Progress-Method Critique`. The checkpoint should decide whether to stop this
  IRQ-defer slice, keep only the useful diagnostic logging, or revise toward
  deterministic ordering before the first watched read.
