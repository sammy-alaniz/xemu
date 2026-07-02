# 328 - pcrtc final-window BQL runtime

## Purpose

- One new fact this run was supposed to produce: whether the BQL-safe
  final-window PCRTC IRQ path avoids the `bql_locked()` abort and changes
  `browser_pre_stream_vector_service_state`.

## Command(s)

```sh
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_REAL_B3_OUT_DIR=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1 \
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

rg -n "bql_locked|assertion failed|worker-error|BROWSER_BOOT_RESULT|BOOT_SMOKE_RESULT|BROWSER_RUNTIME_TRANSCRIPT result|BROWSER_RUNTIME_SMOKE result|BOOT_REAL_B3_MATRIX_RESULT|REAL_B3_EVIDENCE" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/real-b3-matrix.log

rg -n "BOOT_MARK b6 cpu=|BOOT_MARK b6 pic=|BOOT_MARK b6 iret|vector=0x30|interrupt-vector|hard-irq" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log

rg -n "BOOT_MARK b6 dashboard=xbe-executed( |$)|dashboard=xbe-executed-detector-proof|dashboard=xbe-exec-section-miss" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log

rg -n "BOOT_MARK b6 pfifo=stream-idle|BOOT_MARK b6 memory-watch|BOOT_MARK b6 tick-block=complete" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log`
- Fixture assumptions: local MCPX, flash, EEPROM, and HDD assets were supplied;
  no DVD asset was supplied; native WASM and browser-block phases were skipped.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_pre_stream_vector_service_state`

## Findings

- Result:
  `browser_pre_stream_vector_service_state=pcrtc-final-window-irq-pending-at-transition-not-serviced`.
- Important marker/comparator lines:
  - The previous `bql_locked()` abort is gone. The browser run timed out
    normally at the 150 second limit:
    `BOOT_SMOKE_RESULT reason=browser-main-timeout` and
    `BROWSER_BOOT_RESULT result=timeout`.
  - Browser runtime evidence still passed with real assets and B4 display
    capture:
    `BROWSER_RUNTIME_TRANSCRIPT result=pass ... b4_marker=yes display_capture=yes`.
  - Dashboard read/load/entry-ready and section-map evidence still appeared:
    `dashboard=xbe-loaded`, `dashboard=xbe-entry-probe ... status=ready`, and
    `dashboard=xbe-section-map ... status=ready`.
  - The final-window gate still fired once at the intended PFIFO boundary:
    `nv2a=pcrtc-prestream-gate ... action=allow ... dma_get_before=0x03881314 dma_get_after=0x03881318 dma_put=0x03881318 ... entry_ready=yes ... stream_idle_seen=no`.
  - The PCRTC IRQ was raised without aborting:
    `nv2a=irq-line ... line=assert reason=pcrtc ... pmc_pending=0x01000000 ... pcrtc_pending=0x00000001`.
  - At the PFIFO stream-idle transition, CPU interrupt state was pending:
    `pfifo=stream-idle-transition ... pmc_pending=0x01000000 ... pcrtc_pending=0x00000001 ... cpu_interrupt_request=0x00000002 pending_interrupt=yes cpu_exit_request=yes`.
  - No exact CPU vector service or IRET marker was found for this PCRTC path.
    The only exact CPU hard-IRQ marker in the focused search was a later PIT
    line after stream-idle, not a pre-stream PCRTC service.
  - The guest observed and cleared the PCRTC/PMC pending state later:
    `pmc-access ... NV_PMC_INTR_0 ... value=0x01000000`, followed by
    `nv2a=irq-source ... source=pcrtc op=intr-clear`.
  - Strict dashboard execution still did not occur. The run has only
    `dashboard=xbe-executed-detector-proof` and later repeated
    high-alias-mismatch probes around `0x8001b030`; no strict
    `dashboard=xbe-executed` marker appeared.
  - The watched-word path improved far enough to show two writes:
    first `0x00000000 -> 0x00002710`, then `0x00002710 -> 0x00004e20`.
    The second `tick-block=complete` reports `pre_watch_ticks=1`,
    `post_watch_ticks=2`, and `stream_idle_transition_seen=yes`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  B4/B5/read/load/entry-ready/section-map evidence remained present.
  Stream-idle evidence remained present. IRET/vector-service evidence did not
  appear for the final-window PCRTC IRQ, so the pre-stream service objective is
  still not satisfied.

## Decision

- Status: current
- Why:
  The ownership patch succeeded at its first purpose: it made the final-window
  PCRTC IRQ BQL-safe and avoided the abort. The remaining blocker is sharper:
  the IRQ can become pending at the PFIFO transition, but it is not serviced as
  a pre-stream vector before the guest clears/continues into the later
  high-alias mismatch loop.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/327-pcrtc-final-window-bql-build-loop-check.md` approved exactly
  this runtime and said to switch back to code inspection if the field did not
  move to real pre-stream vector service.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The prior critique said the field remains upstream of strict dashboard
  execution, visible main-menu proof, and game launch, but another runtime
  variant is not justified if this one does not reach/explain pre-stream
  service.
- If yes, process adjustment for next 2-3 turns:
  Do not rerun or tune PCRTC/PFIFO/timer knobs. The next step must inspect why
  a pending PCRTC IRQ at PFIFO stream-idle transition does not produce an exact
  pre-stream vector/IRET service marker.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  If approved, inspect code/log ordering for
  `pcrtc_irq_pending_but_no_pre_stream_vector_service` only. Do not run another
  browser runtime or tune the final-window gate.
