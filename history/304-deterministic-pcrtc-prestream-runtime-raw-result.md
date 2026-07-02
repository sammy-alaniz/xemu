# 304 - deterministic PCRTC pre-stream runtime raw result

## Purpose

Run the approved corrected browser-runtime retry for the deterministic PCRTC
pre-stream design. The one loop-guard field this run could change or explain
was `pre_service_browser_first_watch_read_ticks`, by testing whether the browser
can deliver a pre-stream PCRTC-style service before the first watched
`0x0003a890` read.

## Exact command

```sh
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
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

## Inputs and artifacts

- Output directory:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1`
- Browser runtime log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/browser-runtime.log`
- Fixture manifest:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v1/real-fixture-manifest/real-fixture-manifest.md`

## Loop-guard fields

- `pre_service_browser_first_watch_read_ticks`
- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`

## Findings

1. Corrected fixture preflight passed: flash, HDD, MCPX, and EEPROM were all
   present through explicit environment paths.
2. The browser runtime started with the intended diagnostic knobs:
   `browser_boot_deterministic=1`,
   `browser_boot_deterministic_pcrtc_prestream=1`, and
   `browser_headless_timer_pump_mode=pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty`.
3. The runtime reached selected-assets mode, validated browser capabilities,
   validated assets, and opened the HDD through the browser block backend.
4. The browser run timed out after about 150 seconds:
   `BOOT_SMOKE_RESULT reason=browser-main-timeout elapsed_ms=150051 exit=124`
   and `BROWSER_BOOT_RESULT result=timeout`.
5. The browser-runtime smoke wrapper still reported `result=pass` for the
   browser runtime harness and `BOOT_REAL_B3_MATRIX_RESULT result=pass`, but the
   final evidence wrapper exited non-zero with
   `REAL_B3_EVIDENCE result=fail reason=missing-b3-matrix-pass`.
6. The raw transcript reports `b4_marker=no` and `display_capture=no`. This run
   therefore did not preserve the B4/B5 display baseline and cannot be promoted.
7. Early deterministic markers show expired virtual timers while the exact gate
   stayed blocked before entry-ready:
   `reason=deterministic-blocked`, `entry_ready=no`, `deterministic_ready=no`,
   `virtual_has_timers=yes`, `virtual_expired=yes`.

## Decision

Do not promote this runtime path. The exact PCRTC pre-stream gate did not simply
advance the current B6 boundary; the raw result regressed display capture and
needs static log inspection before any retry.

## Next step

Run the required bounded sub-agent loop check before any checker, comparator,
new runtime, or code change. If approved, inspect this artifact only to identify
whether the failure is absence of `entry_ready`, absence of the exact
`pcrtc/intr-clear` wait state, or a gate that is too strict for browser ordering.
