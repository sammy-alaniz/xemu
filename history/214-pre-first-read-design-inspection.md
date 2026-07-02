# 214. Pre-First-Read Design Inspection

## Purpose

Perform the static design inspection required by
`history/213-pre-first-read-design-inspection-loop-check.md`.

The one field this inspection could change or explain was
`pre_first_read_design_viability`: whether a deterministic pre-first-read
timeline can use an emulation-thread hook that avoids the quarantined
before-interrupt scheduler path.

## Commands

```sh
rg -n 'pre-first-read|PRE_FIRST_READ|micro-scheduler|scheduler=pre-first-read|before_interrupt|before-interrupt|tcg_timer_pump_before_interrupt|pit-pre-first-read|TICK_BLOCK|FIRST_READ|0x80014f32|0x80030e84' \
  xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs

sed -n '960,1125p' accel/tcg/cpu-exec.c
sed -n '1125,1235p' accel/tcg/cpu-exec.c
sed -n '630,735p' accel/tcg/cpu-exec.c
sed -n '1320,1725p' xemu-xbe.c
sed -n '1840,2020p' xemu-xbe.c
sed -n '2570,2710p' xemu-xbe.c
sed -n '10480,10570p' xemu-xbe.c
sed -n '560,610p' xemu-xbe.h
sed -n '1510,1735p' xemu-xbe.c
sed -n '1735,1875p' xemu-xbe.c
sed -n '1875,2025p' xemu-xbe.c

rg -n "pre_first_read_scheduler|tick_block_irq_defer|tcg_timer_pump_before_tb|tcg_timer_pump_after_tb|tcg_timer_pump_before_interrupt|TICK_BLOCK_PC|FIRST_READ_PREDECESSOR" \
  xemu-xbe.c xemu-xbe.h accel/tcg/cpu-exec.c

sed -n '2014,2198p' xemu-xbe.c
sed -n '4125,4395p' xemu-xbe.c
sed -n '4800,4845p' xemu-xbe.c
sed -n '7200,7240p' xemu-xbe.c
sed -n '1260,1290p' accel/tcg/cpu-exec.c

rg -n "pre-first-read|before-interrupt|micro-scheduler|pit-pre-first-read|pit-post-pfifo-pre-first-read|after-TB|after-tb|first watched read|first-read" \
  history goal.md

sed -n '1,220p' history/213-pre-first-read-design-inspection-loop-check.md
ls history
sed -n '1,130p' history/116-pre-first-read-scheduler-ownership-inspection.md
sed -n '1,150p' history/118-emulation-thread-checkpoint-site-inspection.md
sed -n '1,140p' history/136-pre-first-read-tcg-ordering-audit.md
sed -n '1,140p' history/162-pre-first-read-serviceable-window-audit.md
sed -n '1,130p' history/180-before-interrupt-quarantine-runtime-restored-boundary.md
```

## Inputs and Artifacts

- Source inspected:
  `accel/tcg/cpu-exec.c`, `xemu-xbe.c`, and `xemu-xbe.h`
- Prior design/history entries:
  `history/116-pre-first-read-scheduler-ownership-inspection.md`,
  `history/118-emulation-thread-checkpoint-site-inspection.md`,
  `history/136-pre-first-read-tcg-ordering-audit.md`,
  `history/162-pre-first-read-serviceable-window-audit.md`,
  `history/180-before-interrupt-quarantine-runtime-restored-boundary.md`,
  `history/212-stable-baseline-next-field-selection.md`, and
  `history/213-pre-first-read-design-inspection-loop-check.md`
- Stable browser baseline remains:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Fields

- `pre_first_read_design_viability`
- `browser_first_watch_read_ticks`
- `browser_post_service_top_edge`
- strict B6 `dashboard=xbe-executed`

## Findings

- The quarantined hook is exactly the `cpu_exec_loop()` call site before
  `cpu_handle_interrupt()`. It calls
  `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()`, and that helper
  currently returns `false` with a quarantine comment. This path must stay off.
- The existing pre-first-read micro-scheduler was written to be owned by that
  before-interrupt hook. Its active owner strings are `tcg-pre-interrupt`, and
  the arming comment says it runs before `cpu_handle_interrupt()`.
- With the before-interrupt hook quarantined, the current micro-scheduler mode
  cannot arm as designed. `xemu_xbe_boot_trace_tcg_timer_pump_after_tb()` also
  suppresses the normal after-TB pump when the pre-first-read scheduler site is
  ready, so simply selecting `pit-pre-first-read-micro-scheduler` does not
  produce a useful non-quarantined owner.
- The after-TB pump is not enough for the primary metric. `history/136` already
  explains that it runs after transition observations and does not produce the
  watched-word value before the first `0x80014f32->0x80030e84` read.
- A viable non-quarantined hook does exist: the pre-TB point inside
  `cpu_loop_exec_tb()`, after the pre-TB observation helpers and before
  `cpu_tb_exec()`. This hook is emulation-thread-owned and already calls
  `xemu_boot_trace_tcg_timer_pump()` for the old pre-TB mode.
- The pre-TB hook can avoid all rejected behavior if the mode is opt-in and
  does not enable exact-PC IRQ defer. It should not mutate
  `interrupt_request`, `exit_request`, or icount state. Timer callbacks should
  assert normal QEMU/PIC state, and normal CPU execution should decide whether
  the interrupt is delivered before the watched `0x80030e84` TB.
- The useful target PC remains the exact browser predecessor `0x80014f32`
  after PFIFO stream-idle with `IF=1` and `HF_INHIBIT_IRQ_MASK=1`, as found in
  `history/162`. Broadening to earlier PCs such as `0x80014f3d` remains
  rejected because those observations were before PFIFO stream-idle and on the
  wrong path.
- The existing scheduler state machine is reusable as instrumentation, but the
  owner labels and arming path should change if code is touched. It already
  has useful stop reasons:
  `dashboard-executed`, `first-read-before-tick-block`,
  `tick-block-before-first-read`, `edge-regressed`, and `tb-budget`.
- The existing gate marker has useful refusal reasons:
  `tb-budget-zero`, `pump-limit-disabled`, `pump-limit-exhausted`,
  `not-loaded`, `scheduler-done`, `edge-decision-already-seen`,
  `no-virtual-timers`, `no-expired-virtual-timer`, and
  `cpu-not-serviceable`.
- Any implementation must preserve the stable browser shape before marker
  interpretation: B4/B5, dashboard read/load/entry-ready, section-map, PFIFO
  stream-idle, vector `0x30` service/IRET, and the
  `0x80030e84->0x80030f31` post-service edge.

## Decision

`pre_first_read_design_viability=pre_tb_hook_viable_with_revision`

Continue only if the next code slice is a small opt-in revision that routes the
pre-first-read scheduler through the pre-TB hook, not through the quarantined
before-interrupt hook. Reject any runtime that merely re-enables or retunes the
before-interrupt scheduler path.

## Progress-Method Critique

This keeps the work aligned with the main-menu/game-load goal because it
targets the known browser/native divergence before strict dashboard execution.
The risk is still diagnostic drag: another marker-only runtime or another
before-interrupt variant would not move the system toward B6. The next action
should be one small guarded code change or no change at all.

## Next Step

Run the required bounded sub-agent loop check before any code change. Ask it to
critique the proposed pre-TB hook specifically, including whether it is
meaningfully different from the quarantined before-interrupt path and whether
the preservation gates are sufficient.
