# 320 - pcrtc final-window runtime

## Purpose

- One new fact this run was supposed to produce: whether the final PFIFO-window
  PCRTC gate can create a browser pre-stream vector-service opportunity before
  PFIFO stream-idle while preserving the current browser boot evidence.

## Command(s)

```sh
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-v1 \
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

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-v1/browser-runtime.log`
- Fixture assumptions: local MCPX, flash, EEPROM, and HDD assets were supplied;
  `XEMU_REAL_B3_SKIP_NATIVE_WASM=1` and `XEMU_REAL_B3_SKIP_BROWSER_BLOCK=1`
  limited the run to the browser runtime slice.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_pre_stream_vector_service_state`

## Findings

- Result: failed run, but with a useful narrower blocker.
- Important marker/comparator lines:
  - Browser fixture preflight passed and applied the intended deterministic
    knobs, including `browser_boot_deterministic_pcrtc_prestream=1`,
    `pcrtc_vblank_mode=off`, and
    `browser_headless_timer_pump_mode=pcrtc-intr-clear-before-stream-idle-then-after-pfifo-empty`.
  - B4 display capture was present in the runtime transcript.
  - The new final-window marker fired at the intended one-word PFIFO boundary:
    `BOOT_MARK b6 nv2a=pcrtc-prestream-gate context=browser-runtime seq=431 action=allow reason=deterministic-prestream-final-window trigger=pfifo-final-window dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 pending_bytes=4 method=0x1d90 parameter=0x00000000 available=1 processed=1 ... entry_ready=yes dashboard_observed=yes stream_idle_seen=no`.
  - The PCRTC vblank gate also allowed the one-shot deterministic raise:
    `BOOT_MARK b6 nv2a=pcrtc-vblank-gate context=browser-runtime mode=off action=allow reason=deterministic-prestream-final-window count=1`.
  - Immediately after asserting the IRQ line, the browser worker aborted:
    `ERROR:../system/cpus.c:286:cpu_interrupt: assertion failed: (bql_locked())`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  The run did not reach a full comparable preservation window because the
  process aborted at IRQ assertion. It did reach browser runtime setup and B4
  display capture before the abort.

## Decision

- Status: failed run
- Why: the patch proved the final-window gate can identify the intended
  pre-stream PFIFO boundary, but it also proved the IRQ mutation is currently
  occurring from a context where QEMU requires the Big QEMU Lock. The next
  blocker is lock/thread ownership for deterministic PCRTC IRQ delivery, not
  further gate tuning.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/319-pcrtc-final-window-gate-build-loop-check.md` approved exactly
  one targeted runtime to judge `browser_pre_stream_vector_service_state`.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The prior checkpoint said the method was still moving toward strict dashboard
  execution because it targeted the missing browser pre-stream service state,
  but required one-shot handling after the runtime.
- If yes, process adjustment for next 2-3 turns:
  Treat this branch as a lock/thread ownership bug. Do not tune PFIFO windows,
  pump counts, PCRTC vblank modes, or timer limits from this result.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  If approved, inspect or patch only the BQL-safe delivery path for the
  deterministic final-window PCRTC IRQ, preserving the current gate semantics.
