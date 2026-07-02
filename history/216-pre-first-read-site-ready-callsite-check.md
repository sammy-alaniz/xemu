# 216. Pre-First-Read Site-Ready Callsite Check

## Purpose

Check whether the existing pre-first-read scheduler gate-emitting predicate is
called anywhere before changing the scheduler owner.

The one field this probe could explain was
`pre_first_read_scheduler_gate_emit_coverage`.

## Command

```sh
rg -n "pre_first_read_scheduler_site_ready\\(true\\)|pre_first_read_scheduler_site_ready\\(" xemu-xbe.c
```

## Inputs and Artifacts

- Source file: `xemu-xbe.c`
- Prior design entry:
  `history/214-pre-first-read-design-inspection.md`

## Loop-Guard Fields

- `pre_first_read_scheduler_gate_emit_coverage`
- `pre_first_read_scheduler_owner`

## Findings

The only call sites are:

- the function definition;
- the scheduler ready predicate calling
  `xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready(false)`;
- the after-TB pump predicate also calling it with `false`.

No call site uses `emit_gate=true`, so the existing
`scheduler=pre-first-read-gate` marker is currently unreachable after the
quarantine changes unless another call site is added.

## Decision

`pre_first_read_scheduler_gate_emit_coverage=none`

This does not change the design decision from `history/215`; it sharpens the
implementation guard. The pre-TB slice should either intentionally stay
behavior-only and marker-light, or add a bounded gate-emitting call in a very
specific close-window path. It must not reintroduce broad marker-only runtime
behavior.

## Next Step

Run the required loop check before applying the code change.
