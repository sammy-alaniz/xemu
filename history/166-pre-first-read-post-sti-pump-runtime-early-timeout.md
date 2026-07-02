# Pre-First-Read Post-STI Pump Runtime Early Timeout

## Purpose

- One new fact this run was supposed to produce: `post_sti_first_read_predecessor_timer_pump`, judged first by whether `scheduler=pre-first-read phase=start` appears at or near `0x80014f32`.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1

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
XEMU_BROWSER_RUNTIME_PORT=8849 \
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
  > build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log \
  2>&1

rg -n 'scheduler=pre-first-read|tcg=timer-pump|scheduler=pre-first-read-gate' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
sed -n '1,180p' build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
tail -180 build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
rg -n 'BOOT_MARK|ERROR|Error|error|Exception|timeout|BROWSER_RUNTIME|DISPLAY|dashboard|pfifo|headless|timer|B3|B4|B5' \
  build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
wc -l build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Output directory/log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Fixture assumptions: real browser runtime with Firefox BiDi, rebuilt wasm in `build-wasm-pic`, PCRTC vblank off, ready-edge host pump still capped at 4 progress events, memory watch on physical `0x0003a890` write access.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_first_read_predecessor_timer_pump`.

## Findings

- Result: failed run; it did not reach the field under test.
- `BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout`, but only because B3/browser-block evidence exists.
- `DISPLAY_CAPTURE_EVIDENCE result=fail reason=missing-b4-marker`.
- Raw dashboard loaded check failed: `reason=missing-xbe-read-marker`.
- No `scheduler=pre-first-read`, `scheduler=pre-first-read-gate`, or `tcg=timer-pump` markers appeared.
- The log has only 375 lines.
- The run timed out at `BOOT_SMOKE_RESULT reason=browser-main-timeout elapsed_ms=90052 exit=124`.
- It was still in early storage activity; the latest relevant disk path was `read_lba=4609024`, before the dashboard XBE read/load markers from the focused B6 artifacts.
- The runtime did not reach B4 display capture, dashboard XBE read/load, entry-ready, PFIFO stream-idle, the post-service watch edge, or strict B6.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Yes for this artifact, but the artifact never reached the scheduler boundary and should not be interpreted as evidence against the post-STI scheduler change.

## Decision

- Status: failed run
- Why: the run did not reach dashboard read/load or entry-ready, so it cannot answer `post_sti_first_read_predecessor_timer_pump`. It changes the next action because another immediate runtime would risk repeating an early-timeout mode.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/165` approved one runtime validation only; this run failed before the validation point.

## Next Step

- Narrow follow-up: run the required loop check. The checkpoint should decide whether to retry the same runtime once as an early-timeout flake, first inspect setup/log differences, or stop this runtime branch.
