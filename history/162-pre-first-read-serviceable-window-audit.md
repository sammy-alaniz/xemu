# Pre-First-Read Serviceable Window Audit

## Purpose

- One new fact this run was supposed to produce: `serviceable_window_revision_target`, using no-emulation log/code comparison after the entry-ready gate runtime.

## Command(s)

```sh
rg -n 'entry-ready|memory-watch-install|pfifo=stream-idle|edge-decision|tick-block=complete|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack|0x80014f' \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log

rg -n 'entry-ready|memory-watch-install|pfifo=stream-idle|edge-decision|tick-block=complete|headless=timer-pump-step|main-loop=timers|cpu=hard-irq-service|cpu=iret|pic=irq-ack|0x80014f' \
  build-real-b3-matrix/browser-pre-first-read-entry-ready-gate-v1/browser-runtime.log

rg -n 'scheduler=pre-first-read-gate|scheduler=pre-first-read context|tcg=timer-pump|timer-pump-bql' \
  build-real-b3-matrix/browser-pre-first-read-entry-ready-gate-v1/browser-runtime.log \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log

rg -n 'xemu_xbe_exec_context_is_pre_first_read_scheduler_serviceable|pre_first_read_scheduler_gate_should_emit|pre_first_read_scheduler_gate_emit|xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready' \
  xemu-xbe.c

sed -n '1528,1568p' xemu-xbe.c
sed -n '1984,2060p' xemu-xbe.c
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Gate-marker browser log: `build-real-b3-matrix/browser-pre-first-read-entry-ready-gate-v1/browser-runtime.log`
- Source file: `xemu-xbe.c`
- Fixture assumptions: no emulation run; static/log audit only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `serviceable_window_revision_target`.

## Findings

- Result: revise the serviceable target, but not to `0x80014f3d`.
- The restored-boundary artifact and the gate-marker artifact both visit `0x80014f3d` early after entry-ready while stream-idle is still false and the NV2A wait source is `pcrtc/vblank-suppress`.
- In the restored-boundary artifact, that early `0x80014f3d` path is followed much later by the useful stream-idle path: hard IRQ service around lines 2628-2629, stream-idle kernel-loop samples at lines 2630-2631, host timer progress at lines 2633-2637, `0x80014f31 -> 0x80014f32` at line 2638, and `0x80014f32 -> 0x80030e84` at line 2639.
- At restored-boundary line 2638, the useful `0x80014f32` predecessor is after PFIFO stream-idle and has `interrupts_enabled=yes` but `irq_inhibited=yes`. This is the exact reason the current serviceable predicate rejects it.
- The current predicate rejects any `HF_INHIBIT_IRQ_MASK` before checking the PC, even for `XEMU_XBE_FIRST_READ_PREDECESSOR_PC_BROWSER`.
- The current predicate allows only `0x8001b030`, `0x80014f32`, and `0x80014f5f`, and requires no pending interrupt and no IRQ-inhibit.
- The gate-marker artifact consumed all 64 entry-ready markers before PFIFO stream-idle and never reached the restored-boundary post-stream-idle `0x80014f32` point. It therefore supports reducing marker perturbation/noise before stream-idle.
- The gate-marker artifact's `0x80014f3d` observations are not good service points: they are before PFIFO stream-idle, have `irq_inhibited=yes`, and branch to `0x8001ae75`, not directly to the shared watched-word read.
- No evidence supports broadening to `0x80014f3d`.
- The better target is the exact browser predecessor `0x80014f32` after PFIFO stream-idle with `IF=1` and `HF_INHIBIT_IRQ_MASK=1`: pump the timer there so any IRQ becomes pending and can be delivered after the RET, before executing the `0x80030e84` watched-word read.
- Marker perturbation should be reduced by making `scheduler=pre-first-read-gate` close-window only, for example only when PFIFO stream-idle has been observed or the PC is one of the exact scheduler candidate PCs.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: the static/log audit identifies a concrete code target. The current predicate is too strict at the exact useful `0x80014f32` browser predecessor because it rejects the post-STI IRQ-inhibit state. Broadening to the earlier `0x80014f3d` would target the wrong pre-stream-idle path.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: `history/161` required choosing one of broaden serviceable window, reduce marker perturbation, or stop. The audit chooses a targeted serviceable-window revision plus a close-window marker filter; it rejects broadening to `0x80014f3d`.

## Next Step

- Narrow follow-up: run the required loop check. Proposed code change: allow the exact browser first-read predecessor `0x80014f32` with `IF=1` and `HF_INHIBIT_IRQ_MASK=1` as a timer-pump point, while keeping broad IRQ-inhibited states rejected and reducing gate-marker emission to stream-idle or exact candidate PCs.
