# Guarded Preinterrupt Scheduler Runtime Fixture Preflight Fail

## Purpose

- One new fact this run was supposed to produce: whether the guarded
  pre-first-read scheduler changes the browser runtime field
  `guarded_preinterrupt_scheduler_runtime_effect`.

## Command(s)

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v1 \
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
  `build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v1/real-b3-matrix.log`
- Fixture assumptions: local fixture paths or environment variables should have
  provided required flash and HDD assets before browser runtime launch.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `guarded_preinterrupt_scheduler_runtime_effect`.

## Findings

- Result: failed before browser runtime or emulation.
- Important marker/comparator lines:
  `REAL_FIXTURE_READY item=flash status=missing source=not-found`;
  `REAL_FIXTURE_READY item=hdd status=missing source=not-found`;
  `REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures require=1`;
  `BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not
  measured; no runtime started.

## Decision

- Status: failed run
- Why: the run stopped in fixture preflight, so it does not support or refute
  the guarded scheduler patch.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history 339 approved exactly one runtime after the
  build, with no automatic rerun if it failed early.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: history 339 said the runtime was a
  valid first effect test of a guarded code change, but should not be repeated
  blindly.
- If yes, process adjustment for next 2-3 turns: treat fixture restoration as a
  separate field before any runtime retry.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique,
  asking whether fixture discovery should be the next action and whether the
  runtime remains non-repeatable until fixture sources are restored.
