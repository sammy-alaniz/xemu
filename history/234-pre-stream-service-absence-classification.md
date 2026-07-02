# Pre Stream Service Absence Classification

## Purpose

- One new fact this run was supposed to produce: classify `browser_pre_stream_service30_absence_cause` without adding code or running emulation.

## Command(s)

```sh
rg -n 'irq_after_pfifo_empty_only|main_loop_timer_pump_ready|browser_headless|HEADLESS_TIMER|pfifo-ready-edge|browser-ready-edge|timer-pump-gate|pump_ready|pcrtc-before|vblank-suppress|qemu_clock_run|main-loop=timers' xemu-xbe.c ui/xemu-headless.c util/main-loop.c accel/tcg/cpu-exec.c
sed -n '2440,2498p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n -m 100 'pfifo=stream-idle-transition|pfifo=stream-idle-boundary|main-loop=timers|pit=irq-timer|cpu=hard-irq|pic=irq-ack|cpu=iret|headless=timer-pump' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n -m 120 'pfifo=stream-idle-transition|pfifo=stream-idle-boundary|main-loop=timers|pit=irq-timer|cpu=hard-irq|pic=irq-ack|cpu=iret' build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
sed -n '1031,1168p' xemu-xbe.c
sed -n '170,235p' ui/xemu-headless.c
sed -n '640,830p' ui/xemu-headless.c
sed -n '6860,6915p' xemu-xbe.c
sed -n '10360,10385p' xemu-xbe.c
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: static-only inspection, no new runtime artifact
- Fixture assumptions: current browser baseline uses the ready-edge plus bounded host fallback mode and keeps `XEMU_BOOT_TRACE_XBE_IRQ_AFTER_PFIFO_EMPTY_ONLY=1`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `browser_pre_stream_service30_absence_cause`

## Findings

- Result: `browser_pre_stream_service30_absence_cause=browser-timer-irq-deliberately-gated-until-pfifo-empty`.
- The browser baseline has no pre-stream PIT rising edge, no pre-stream hard IRQ set, no pre-stream PIC ack for vector `0x30`, and no pre-stream vector `0x30` service. That matches the previous comparator result, not a marker gap.
- Browser `headless=timer-pump-gate` markers after entry-ready but before stream-idle report `pump_ready=no`; the first `main-loop=timers` marker appears at the PFIFO stream-idle transition.
- At the first browser ready-edge timer pump, `virtual_expired_before=yes` and `timer_progress=yes`, so timers were not fundamentally unavailable. They were held until the PFIFO readiness gate opened.
- Source inspection matches the log ordering:
  - `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` returns PFIFO-empty readiness for ready-edge modes.
  - The fallback gate also blocks on `xemu_xbe_irq_after_pfifo_empty_only()` when the wait snapshot is not PFIFO-empty.
  - `ui/xemu-headless.c` only calls `qemu_clock_run_timers_with_attrs_limit()` after `xemu_headless_browser_timer_pump_ready()` or deterministic warmup grants readiness.
  - `xemu_xbe_boot_trace_observe_main_loop_timers()` suppresses regular non-browser diagnostic timer observations unless the same readiness path is open.
- Native does not share this browser-headless gate: it emits repeated pre-stream `pit=irq-timer`, hard IRQ set, `pic=irq-ack irq=30`, vector `0x30` service, and IRET markers before the first watched read.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was static inspection of frozen passing/known-failing artifacts.

## Decision

- Status: current
- Why: the next valid target is no longer "why does the CPU/PIC not service vector `0x30` pre-stream?" in the abstract. The immediate cause is that browser-headless timer delivery is intentionally withheld until the PFIFO wait gate opens, so the PIT IRQ chain cannot exist pre-stream.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/233-pre-stream-service-classification-loop-check.md` approved one static classification only, with a progress-method critique requiring that this distinguish deliberate gating from timer expiry, PIC, CPU-serviceability, or marker-coverage causes before any further runtime/code work.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique, then choose one baseline-preserving design change that can relax or replace the browser pre-stream timer/IRQ gate without weakening the B6 checker or repeating quarantined scheduler/pump branches.
