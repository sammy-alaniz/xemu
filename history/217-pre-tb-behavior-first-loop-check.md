# 217. Pre-TB Behavior-First Loop Check

## Purpose

Run the required bounded loop check after
`history/216-pre-first-read-site-ready-callsite-check.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/214-pre-first-read-design-inspection.md`
- `history/215-pre-tb-scheduler-loop-check.md`
- `history/216-pre-first-read-site-ready-callsite-check.md`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`
- `pre_first_read_scheduler_gate_emit_coverage`

## Findings

The sub-agent decision was `continue`.

It agreed that the missing `emit_gate=true` call site matters, but said it
does not block the pre-TB owner change. The next patch should be
behavior-first and marker-light, not another gate-diagnostic pass.

Recommended scope:

- route the opt-in pre-first-read scheduler through the existing pre-TB hook in
  `cpu_loop_exec_tb()`;
- keep `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` quarantined;
- do not revive exact-PC IRQ defer;
- do not manually mutate interrupt/exit/icount state;
- target the known useful path, especially `0x80014f32` after PFIFO
  stream-idle, not `0x80014f3d`;
- keep markers limited to compact start/stop outcome markers already tied to
  scheduler behavior;
- if gate emission is added later, make it close-window only and tightly
  bounded.

Progress-method critique: this is still connected to strict browser dashboard
execution, main menu, and game load because it targets the live
native/browser divergence before B6. The danger is repeating the failed
diagnostic pattern by adding more marker plumbing without changing behavior.
The checkpoint recommends one small pre-TB behavior slice, build, then one
preservation-gated runtime later.

## Decision

Continue.

## Next Step

Patch only the pre-TB scheduler owner routing and owner labels. Do not add a
new broad gate marker path in this slice.
