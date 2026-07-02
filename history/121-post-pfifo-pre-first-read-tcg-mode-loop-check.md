# Post PFIFO Pre First Read TCG Mode Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the new opt-in
  TCG-owned mode from `history/120` justifies exactly one browser runtime
  validation.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Read history/120 in addition to prior context. Evaluate the new code candidate:
one opt-in TCG mode, pit-post-pfifo-pre-first-read, parsed in xemu-xbe.c,
PIT-only, gated to PFIFO stream idle observed, PFIFO-empty wait, no tick-block
completion, no edge-decision marker, serviceable idle-loop CPU context with no
pending interrupt, virtual timers present and expired, and delivery attempts
capped by XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT. The mode does
not manually mutate interrupt_request, exit_request, or icount high-half, and
the podman WASM build passed after escalation. Answer the standard loop-check
questions, include Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Code/build summary:
  `history/120-post-pfifo-pre-first-read-tcg-mode-build.md`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `tcg_timer_pump_mode_seen`, `pre_first_read_tcg_checkpoint_active`,
  `browser_first_watch_read_ticks`, `browser_post_service_top_edge`, and
  `browser_dashboard_xbe_executed`.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping if the next step is exactly one validation of the
  new TCG-owned mode.
- It said this is not another host-pump count or exact-PC defer variant because
  it changes the ownership field to `pre_first_read_tcg_checkpoint_active`.
- The narrowest next fact is whether the new mode emits
  `tcg=timer-pump mode=pit-post-pfifo-pre-first-read` before the first watched
  read, and whether that moves `browser_first_watch_read_ticks` above the
  current baseline without breaking the useful post-service edge.
- It killed exact-PC IRQ defer again.
- It kept that the watched word must advance through normal guest tick-block
  execution after normal PIT/PIC interrupt delivery.
- It revised the runtime hypothesis to a specific question: emulation-thread
  TCG delivery may be stable enough where browser headless host-pump delivery
  was not.
- It approved exactly one browser runtime validation before further code
  expansion.
- Recommended command shape:
  - Keep ready-edge host4 host-pump settings unchanged.
  - Keep exact-PC defer disabled/quarantined.
  - Use `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read`.
  - Use `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1`.
  - Use bounded `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT`, for
    example `4`.
  - Keep memory-watch, tick-block, edge-decision, PIC, hard-IRQ, IRET, and
    section-map diagnostics.

## Decision

- Status: current.
- Why: one runtime is justified because the code is opt-in, bounded, PIT-only,
  avoids manual CPU state mutation, and directly targets the current boundary.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: judge the run in order by
  `tcg_timer_pump_mode_seen`, `pre_first_read_tcg_checkpoint_active`,
  `browser_first_watch_read_ticks`, `browser_post_service_top_edge`,
  `post_service_edge_classification`, and strict
  `browser_dashboard_xbe_executed`.

## Progress-Method Critique

- The critique said the method is still moving toward strict dashboard
  execution because it targets the tick/CPU ordering gap that blocks
  browser-runtime `dashboard=xbe-executed`; visible main-menu proof and game
  launch still depend on that gate.
- It said this is diagnostic, but not rerun-heavy yet, because the
  implementation changed ownership from host polling to the TCG CPU loop.
- Process adjustment for the next 2-3 turns: run exactly one validation and do
  not expand the mode unless it either emits the checkpoint marker or explains
  why the checkpoint gate never opens.

## Next Step

- Narrow follow-up: run exactly one browser validation with the new TCG mode and
  reduce it with strict B6, pre-service tick-gap, post-service edge-decision,
  and section-map checks.
