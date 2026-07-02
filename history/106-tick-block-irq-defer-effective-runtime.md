# Tick Block IRQ Defer Effective Runtime

## Purpose

- One new fact this run was supposed to produce: whether using captured CPU
  context as the effective interrupt/exit state makes the one-TB IRQ defer
  engage at `0x80030e84`, and whether that moves the watched-word timing toward
  native.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

mkdir -p build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1

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
XEMU_BROWSER_RUNTIME_PORT=8844 \
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
  > build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1/browser-runtime.log \
  2>&1

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log effective=build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log

rg -n "tick-block-irq-defer|tick-block=complete|edge-decision context=browser-runtime|memory-watch .* access=write|main-loop=timers|cpu=hard-irq|cpu=hard-irq-service|iret|DASHBOARD_LOADED_EVIDENCE|SECTION_MAP" \
  build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1/browser-runtime.log`
- Combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-effective-readyedge-host4-v1-combined.log`
- Fixture assumptions: podman-backed rebuilt WASM, Firefox BiDi browser
  runtime, real MCPX/flash/HDD fixtures, same ready-edge host4 shape as
  `history/104`, with only the effective-state code revision added.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `irq_defer_engaged`, `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: build passed and linked `qemu-system-i386.js`; browser runtime exited
  `0`; combined evidence was written.
- The browser transcript proves the mode was applied:
  `trace_xbe_tick_block_irq_defer=1` and
  `trace_xbe_tick_block_irq_defer_limit=8`.
- Strict B6 still correctly failed:
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.
- Section-map evidence still passed.
- The effective-state fix worked for the immediate field:
  `tick-block-irq-defer phase=pre action=defer
  reason=defer-one-tick-block effective_interrupt_request=0x00000002
  effective_exit_request=yes sample_mismatch=yes`.
- The defer restored the IRQ after the first attempted TB:
  `tick-block-irq-defer phase=post ... expected_path=no tb_exit=3
  saved_interrupt_request=0x00000002 post_interrupt_request=0x00000000
  restored_interrupt_request=0x00000002`.
- The first deferred TB did not complete the block; it exited
  `0x80030e84->0x80030e84`.
- After the IRQ service and IRET back to `0x80030e84`, the second pass skipped
  defer because no hard IRQ was pending, then the tick block completed:
  `tick-block=complete ... pre_stream_idle_completion=no
  edge_decision_seen_before_completion=yes
  edge_decision_count_before_completion=1
  pre_watch_ticks=0 post_watch_ticks=1`.
- The primary metric did not improve:
  `native_first_watch_read_ticks=136`,
  `browser_first_watch_read_ticks=0`,
  `divergence=browser-first-watch-read-before-catchup`.
- Post-service edge preservation still failed:
  baseline classification is `useful-post-service-edge`; effective run is
  `post-service-edge-diverged`, with top edge `0x80030e4c->0x80030e84`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  B4/B5/read/load/entry-ready/section-map/stream-idle evidence remained
  present, and this run did include an IRET pair back to `0x80030e84`.
  However, the useful post-service edge still regressed and strict B6 did not
  pass.

## Decision

- Status: current diagnostic evidence, not active baseline.
- Why: the code fix made the defer engage, proving the sampled-argument bug was
  real, but the behavioral hypothesis is weaker now: deferring one TB does not
  complete the block before the first zero-tick watched read, and it does not
  preserve the active baseline post-service edge.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/105` allowed exactly this effective-state
  patch plus one validation against `irq_defer_engaged`,
  `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Progress-Method Critique

- The metrics still connect to the final goal because strict browser
  `dashboard=xbe-executed` remains blocked by this CPU/timer ordering gap.
- This result is useful but shows diminishing returns for one-TB IRQ-defer
  tweaks: it changed `irq_defer_engaged`, but not the primary watched-read
  timing or the B6 marker.
- The history/loop-check process is useful here because the next action should
  not be another variant of the same defer without an independent critique.
- The right next mode is a loop-check critique, then likely code inspection of
  why TB exit 3 occurs on the deferred block or a revision away from this
  micro-scheduler path.
- Process adjustment for the next 2-3 turns: do not run another ready-edge
  host4 IRQ-defer validation unless the next field is different from
  `irq_defer_engaged`.

## Next Step

- Narrow follow-up: run the required loop check. The next decision should
  explicitly decide whether to inspect `tb_exit=3`/exit-request handling at the
  deferred block, revise toward a different deterministic scheduler boundary,
  or stop this micro-scheduler slice.
