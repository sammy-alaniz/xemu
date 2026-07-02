# 308 - deterministic PCRTC pre-stream v2 runtime raw result

## Purpose

Run exactly one approved post-patch browser runtime for the deterministic PCRTC
pre-stream branch. The primary field was `browser_pre_stream_vector_service_state`;
the first success condition was preserving B4/B5/dashboard read/load/entry-ready
before judging `pre_service_browser_first_watch_read_ticks`.

## Exact command

```sh
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2 \
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
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2`
- Browser runtime log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/browser-runtime.log`
- Fixture manifest:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deterministic-pcrtc-prestream-v2/real-fixture-manifest/real-fixture-manifest.md`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `native_pre_stream_serviceable_state_browser_mapping`

## Findings

1. Fixture preflight passed with explicit local flash, HDD, MCPX, and EEPROM
   paths.
2. The browser runtime used the intended post-patch deterministic PCRTC knobs:
   `browser_boot_deterministic=1`,
   `browser_boot_deterministic_pcrtc_prestream=1`, and
   `browser_headless_timer_pump_mode=pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty`.
3. Unlike v1, this v2 run restored B4/display evidence:
   `BROWSER_RUNTIME_TRANSCRIPT ... b4_marker=yes display_capture=yes`, with
   repeated `BROWSER_DISPLAY_CAPTURE result=pass` markers.
4. The transcript contains dashboard entry-ready execution-probe evidence after
   the patch, including `entry_ready=yes entry=0x00017d60` in kernel-loop and
   XBE execution transition markers.
5. The runtime still timed out:
   `BOOT_SMOKE_RESULT reason=browser-main-timeout elapsed_ms=150247 exit=124`
   and `BROWSER_BOOT_RESULT result=timeout`.
6. The wrapper reported `BOOT_REAL_B3_MATRIX_RESULT result=pass` for the
   selected browser runtime block, but the final evidence wrapper exited
   non-zero with `REAL_B3_EVIDENCE result=fail reason=missing-b3-matrix-pass`
   because this diagnostic invocation skipped the full native/browser-block
   matrix pieces.
7. Raw output still shows strict B6 is not proven. The visible XBE transition
   sample remains in the kernel alias loop around `0x8001b02f/0x8001b030`, not
   a strict `dashboard=xbe-executed` marker.

## Decision

The boundary-preservation patch worked for the immediate regression: v2 restored
B4/display capture and entry-ready where v1 did not. This is not B6 success.
Further analysis must now classify whether the run reached the post-entry
pre-stream PCRTC/fallback path and whether the watched tick field improved.

## Next step

Run the required bounded sub-agent loop check before combining evidence or
running comparators. If approved, analyze only this v2 artifact with the
existing B6/runtime/section-map/pre-service helpers and record the results in
the next history entry before any more code changes or runtime experiments.
