# 302 - PCRTC Pre-Stream Runtime Fixture Preflight Fail

## Purpose

- One new fact this run was supposed to produce:
  whether the deterministic PCRTC pre-stream mode moves
  `pre_service_browser_first_watch_read_ticks` above 0 while preserving the
  stable ready-edge host4 evidence.

## Command(s)

```sh
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1 \
XEMU_REAL_B3_SKIP_NATIVE_WASM=1 \
XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1 \
XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi \
XEMU_REAL_B3_BROWSER_RUNTIME_MS=150000 \
XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off \
XEMU_BROWSER_BOOT_DETERMINISTIC=1 \
XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM=1 \
XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=1 \
XEMU_BROWSER_BOOT_DETERMINISTIC_WARMUP_PROGRESS_LIMIT=1 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT=32 \
XEMU_BOOT_TRACE_XBE_PIC_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_CPU_HARD_IRQ_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_IRET_LIMIT=256 \
XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_MAIN_LOOP_TIMER_LIMIT=128 \
XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT=4 \
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=0 \
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle-full \
XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1 \
XEMU_BOOT_TRACE_XBE_IRQ_WATCH=0 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS=0x0003a890 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_LIMIT=64 \
XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS=write \
scripts/xbox-real-b3-matrix.sh
```

## Inputs And Artifacts

- Intended output directory:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1`
- Preflight artifacts:
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/real-fixture-manifest/real-fixture-ready.log`
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/real-fixture-manifest/fixture-privacy.log`
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/real-fixture-manifest/real-fixture-manifest.md`
- Fixture assumptions:
  incorrect; this command did not point the harness at the existing local Xbox
  assets.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_service_browser_first_watch_read_ticks`

## Findings

- Result:
  failed before emulation/runtime.
- Important marker/comparator lines:
  - `REAL_FIXTURE_READY item=flash status=missing source=not-found`
  - `REAL_FIXTURE_READY item=hdd status=missing source=not-found`
  - `REAL_FIXTURE_READY_RESULT result=missing-required next=add-fixtures require=1`
  - `BOOT_REAL_B3_MATRIX_RESULT result=fail reason=fixtures`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; the browser runtime never started.

## Decision

- Status: failed run
- Why:
  The command omitted the fixture path environment used by prior successful real
  browser runs. No B6 causal signal was produced.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/301` allowed exactly one bounded runtime, but this attempt stopped at
  fixture discovery before exercising that runtime.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  This failure does not test the method; it only shows the approved run command
  needs the existing fixture path inputs.
- If yes, process adjustment for next 2-3 turns:
  Run a loop check before any retry. If approved, retry only the same bounded
  runtime with corrected fixture paths.

## Next Step

- Narrow follow-up:
  Run the required bounded loop check before any retry or analysis.
