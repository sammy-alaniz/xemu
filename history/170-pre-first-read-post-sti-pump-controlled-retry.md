# Pre-First-Read Post-STI Pump Controlled Retry

## Purpose

- One new fact this run was supposed to produce: `post_sti_retry_reaches_b6_boundary`, using a known-good browser runtime origin/port before interpreting `post_sti_first_read_predecessor_timer_pump`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1

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
XEMU_BROWSER_RUNTIME_PORT=8846 \
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
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-pre-first-read-micro-scheduler \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_PRE_FIRST_READ_SCHEDULER_TB_BUDGET=512 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log \
  2>&1

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
rg -n 'dashboard=xbe-read|dashboard=xbe-loaded|section-map|entry-ready|pfifo=stream-idle|scheduler=pre-first-read|tcg=timer-pump|edge-decision|tick-block=complete|memory-watch|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
tail -80 build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
rg -n 'BROWSER_LOCATION|BROWSER_ARTIFACT|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result|ide=hdd|read_lba=4609024|read_lba=4609032|read_lba=4609192|BROWSER_BLOCK_READ|bmdma=start_dma' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
wc -l build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log
```

## Inputs And Artifacts

- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Failed post-STI browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Retry output log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log`
- Fixture assumptions: known-good port/origin `127.0.0.1:8846`, real browser runtime with Firefox BiDi, rebuilt wasm in `build-wasm-pic`, PCRTC vblank off, ready-edge host pump still capped at 4 progress events, memory watch on physical `0x0003a890` write access.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_retry_reaches_b6_boundary`.

## Findings

- Result: failed run; controlled retry did not reach the B6 boundary.
- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`, but only because B3/browser-block evidence exists.
- `DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker`.
- Raw dashboard loaded check failed: `reason=missing-xbe-read-marker`.
- No dashboard read/load, entry-ready, stream-idle, scheduler, TCG timer-pump, edge-decision, tick-block, or post-service markers appeared.
- The retry used known-good origin `http://127.0.0.1:8846/browser/xbox-boot/`.
- The retry log again has 375 lines and times out at `BOOT_SMOKE_RESULT reason=browser-main-timeout`.
- The retry stops after `read_lba=4609024` / `BROWSER_BLOCK_READ offset=2621440 bytes=4096`, the same early point as the prior failed post-STI run.
- This repeat on the known-good port means the early timeout is no longer explained by port/origin drift alone.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Yes for this artifact. The artifact still does not test the post-STI scheduler field because it never reaches dashboard read/load.

## Decision

- Status: failed run
- Why: the controlled retry repeated the same pre-dashboard-read timeout. `post_sti_first_read_predecessor_timer_pump` remains untested, and another immediate runtime is not justified without explaining why the current build/runtime shape stops at `read_lba=4609024`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/169` approved exactly one controlled retry and required dashboard read/load as the first gate.

## Next Step

- Narrow follow-up: run the required loop check. The next likely mode is static code/log inspection of why the current post-STI build no longer reaches dashboard read/load, or reverting/reducing the post-STI patch if inspection points to early runtime perturbation.
