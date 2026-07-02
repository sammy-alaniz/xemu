# 215. Pre-TB Scheduler Loop Check

## Purpose

Run the required bounded loop check after
`history/214-pre-first-read-design-inspection.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/212-stable-baseline-next-field-selection.md`
- `history/213-pre-first-read-design-inspection-loop-check.md`
- `history/214-pre-first-read-design-inspection.md`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`
- `pre_first_read_design_viability`

## Findings

The sub-agent decision was `continue`.

It found the proposed pre-TB revision non-redundant if tightly scoped. The
important distinction is that it would run inside `cpu_loop_exec_tb()` before
`cpu_tb_exec()`, not before `cpu_handle_interrupt()`, and it does not require
reactivating `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()`.

Required guard for the code slice:

- opt-in mode only;
- keep the before-interrupt hook quarantined;
- no exact-PC IRQ defer revival;
- no manual mutation of `interrupt_request`, `exit_request`, or icount
  high-half state;
- target only the known useful predecessor path, especially `0x80014f32` after
  PFIFO stream-idle;
- do not broaden to `0x80014f3d`;
- preserve strict B6 semantics;
- later runtime interpretation must be gated on B4/B5, dashboard
  read/load/entry-ready, section-map, PFIFO stream-idle, vector `0x30`
  service/IRET, and the `0x80030e84->0x80030f31` post-service edge.

Progress-method critique: the checkpoint says this still moves toward strict
browser dashboard execution, main menu, and game load because it targets the
front-most native/browser divergence. It is not just another marker pass if it
actually changes deterministic emulation-thread ordering and keeps
`browser_first_watch_read_ticks > 1` as the success metric. If the slice
regresses stable shape or leaves the field unchanged, stop this scheduler
branch rather than tuning around it.

## Decision

Continue.

## Next Step

Implement one small opt-in pre-TB scheduler revision. The change must not
reactivate the before-interrupt hook or the exact-PC IRQ defer path.
