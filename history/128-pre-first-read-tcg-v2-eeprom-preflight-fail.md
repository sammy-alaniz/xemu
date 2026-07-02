# Pre First Read TCG V2 EEPROM Preflight Fail

## Purpose

- One new fact this run was supposed to produce:
  whether the updated `pit-post-pfifo-pre-first-read` mode emits
  `tcg=timer-pump` at `0x80030e84` in browser runtime.

## Command(s)

```sh
mkdir -p build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin NODE_PATH= \
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom-v2.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_BROWSER_RUNTIME_MODE=real \
XEMU_BROWSER_RUNTIME_EXPECT_B3=1 \
XEMU_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_BROWSER_RUNTIME_BROWSER=firefox \
XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm-pic \
XEMU_BROWSER_RUNTIME_PORT=8847 \
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
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
scripts/xbox-browser-runtime-smoke.sh \
  > build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log \
  2>&1

sed -n '1,160p' build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log
tail -n 120 build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log
wc -l build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log
```

## Inputs And Artifacts

- Output directory/log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`
- Fixture assumptions: attempted to use a new EEPROM path,
  `/tmp/xemu-b6-eeprom-v2.bin`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  `browser_post_service_top_edge`.

## Findings

- Result: failed before emulation.
- The runtime log has only four lines.
- The fixture preflight failed with:
  `XEMU_EEPROM does not exist: /tmp/xemu-b6-eeprom-v2.bin`.
- The smoke script reported:
  `BROWSER_RUNTIME_SMOKE result=fail reason=fixture-preflight status=2`.
- No browser runtime evidence, B4/B5 evidence, section-map evidence, TCG pump
  marker, or strict B6 evidence was produced.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured; the emulator did not start.

## Decision

- Status: failed run.
- Why: command setup used a new EEPROM path that the fixture preflight rejects.
  This failure does not evaluate the code change.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/127` approved exactly one real runtime
  validation. This preflight failure did not consume that validation because no
  emulator run occurred.

## Progress-Method Critique

- This failure does not move toward strict dashboard execution because it did
  not reach emulation.
- The process is still useful here because the failure is isolated to fixture
  setup instead of being misread as negative B6 evidence.
- Process adjustment: rerun only after the required loop check, using the
  known existing EEPROM path from prior browser runs rather than a new path.

## Next Step

- Narrow follow-up: run the required loop check, then rerun the approved
  browser validation with `XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin`.
