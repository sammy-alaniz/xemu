# Guarded Preinterrupt Scheduler Runtime V2

## Purpose

- One new fact this run was supposed to produce: whether the guarded
  pre-first-read scheduler changes or explains
  `guarded_preinterrupt_scheduler_runtime_effect`.

## Command(s)

```sh
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 \
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=150000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-pre-first-read-micro-scheduler \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4 \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
scripts/xbox-real-b3-matrix.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2/real-b3-matrix.log`
  and
  `build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2/browser-runtime.log`
- Fixture assumptions: explicit environment fixture paths from history 342.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `guarded_preinterrupt_scheduler_runtime_effect`.

## Findings

- Result: partial negative evidence. Fixture preflight and browser runtime pass,
  and the pre-first-read scheduler now starts, but the first watched
  `0x0003a890` read still sees 0 ticks and IRET preservation regresses.
- Important marker/comparator lines:
  `REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=1`;
  `BROWSER_RUNTIME_TRANSCRIPT result=pass`;
  `BROWSER_RUNTIME_SMOKE result=pass`;
  `BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=skipped browser_block=skipped browser_runtime=pass`;
  `REAL_B3_EVIDENCE result=fail reason=missing-b3-matrix-pass`;
  `dashboard=xbe-loaded`;
  `dashboard=xbe-section-map ... phase=entry-ready`;
  `pfifo=stream-idle-boundary`;
  `scheduler=pre-first-read ... phase=start ... guest_pc=0x80014f32 ... watch_value=0x00000000 watch_ticks=0`;
  `scheduler=pre-first-read ... phase=timer-pump ... timer_pumps=1 timer_deliveries=1 ... watch_ticks=0`;
  first watched read remains
  `start_pc=0x80014f32 next_pc=0x80030e84 ... next_mem_addr=0x8003a890 ... next_mem_value=0x00000000`;
  `pic=irq-ack ... intno=0x30`;
  `cpu=hard-irq-service ... intno=0x30`;
  `tick-block=complete ... start_pc=0x80030e84 next_pc=0x80030f31 ... pre_watch_ticks=0 post_watch_ticks=1`;
  no exact `BOOT_MARK b6 dashboard=xbe-executed context=` marker.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? B4,
  B5/browser runtime, dashboard read/load, entry-ready, section-map,
  stream-idle, vector `0x30`, and the `0x80030e84->0x80030f31` tick block are
  preserved. IRET is not preserved in this artifact: exact `iret` marker search
  only found diagnostic configuration lines, not a CPU IRET marker.

## Decision

- Status: negative evidence
- Why: the guarded scheduler fires, but it does not move the first watched read
  above zero. It also loses the baseline IRET marker, so this branch cannot be
  promoted as-is.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history 343 approved exactly one runtime after
  fixture sources were restored.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: history 343 said the retry is valid
  once, but becomes circular if repeated without a new named field.
- If yes, process adjustment for next 2-3 turns: do not retry this runtime
  again. Run the required loop check and ask whether to kill/revise the guarded
  scheduler branch based on the unchanged first-read tick value and missing IRET.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique
  before any further code change, probe, or runtime.
