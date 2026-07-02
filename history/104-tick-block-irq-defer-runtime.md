# Tick Block IRQ Defer Runtime

## Purpose

- One new fact this run was supposed to produce: whether an opt-in one-TB
  hard-IRQ defer at `0x80030e84` can complete the
  `0x80030e84->0x80030f31` tick block before edge-decision consumes the
  zero-tick watched value.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1

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
XEMU_BROWSER_RUNTIME_PORT=8843 \
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
  > build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log irqdefer=build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log

rg -n "tick-block-irq-defer|tick-block=complete|edge-decision|memory-watch|CPU_HARD_IRQ|IRET|main-loop=timers|DASHBOARD_LOADED_EVIDENCE|SECTION_MAP" \
  build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log`
- Fixture assumptions: podman-backed rebuilt WASM, Firefox BiDi browser
  runtime, real MCPX/flash/HDD fixtures, ready-edge host4 baseline shape plus
  diagnostic-only `XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER=1` and
  `XEMU_BOOT_TRACE_XBE_TICK_BLOCK_IRQ_DEFER_LIMIT=8`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: build passed, browser runtime exited `0`, and the combined log was
  written.
- The browser transcript proves the new knobs were applied:
  `trace_xbe_tick_block_irq_defer=1` and
  `trace_xbe_tick_block_irq_defer_limit=8`.
- Strict B6 still correctly failed:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- Section-map evidence still passed.
- The defer marker emitted once, but did not defer:
  `tick-block-irq-defer phase=pre action=skip reason=no-hard-irq`.
- The same marker exposes the implementation bug/ordering race:
  argument `interrupt_request=0x00000000` and `cpu_exit_request=no`, while the
  captured context in that marker shows `ctx_interrupt_request=0x00000002` and
  `ctx_exit_request=yes`.
- No `tick-block=complete` marker appeared in this run.
- The edge-decision probe still consumed the zero state at `0x80030e84`:
  `edge-decision ... start_pc=0x80030e84 next_pc=0x80030e84 tb_exit=3
  pre_watch_value=0x00000000 pre_cpu_interrupt_request=0x00000002`.
- The pre-service comparator remains unchanged at the primary metric:
  `native_first_watch_read_ticks=136`,
  `browser_first_watch_read_ticks=0`, and
  `divergence=browser-first-watch-read-before-catchup`.
- Post-service edge preservation failed for this artifact:
  baseline classification is `useful-post-service-edge`, while this run is
  `block-start-branch-mismatch` with `top_edge=0x8001b02f->0x8001b030` and
  `first_block_edge=0x80030e84->0x80030e84`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  B4/B5/read/load/entry-ready/section-map/stream-idle evidence remained
  present. The useful post-service edge regressed, and the focused comparator
  did not find an IRET pair for this artifact.

## Decision

- Status: negative evidence with a concrete implementation revision.
- Why: the opt-in mode was plumbed and observed, but the decision used the
  stale sampled interrupt arguments instead of the captured CPU context that
  already showed the pending hard IRQ at `0x80030e84`.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: `history/103` authorized one narrow implementation
  plus one validation run judged on
  `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, and post-service edge preservation. This
  run failed those fields but explained why the defer did not engage.

## Progress-Method Critique

- The active metric still connects to strict browser dashboard execution,
  because the browser is failing before it can reach accepted
  `dashboard=xbe-executed`, and main-menu/game launch remain blocked by that.
- This was not a broad rerun: the new field was `irq_defer_sample_mismatch`.
  The artifact explains the failed behavioral change rather than just
  reconfirming `missing-xbe-executed-marker`.
- The history/loop-check process is helping here because it prevents rolling
  directly into another behavioral patch without recording the stale-sample
  finding.
- The right next mode is code revision, not another runtime with the same
  binary.
- Process adjustment for the next 2-3 turns: keep the next change mechanical
  and bounded to the defer decision source, then run exactly one validation
  only if the required loop check agrees.

## Next Step

- Narrow follow-up: run the required loop check. If it says continue/revise
  toward the same slice, change the pre-defer decision to use the captured
  CPU context as the effective interrupt/exit state, log whether the sampled
  argument differed from the captured context, and rerun one validation.
