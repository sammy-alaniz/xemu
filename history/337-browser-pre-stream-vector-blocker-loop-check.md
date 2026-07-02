# 337 - Browser Pre-Stream Vector Blocker Loop Check

## Purpose

Record the required bounded sub-agent loop check after
`history/336-browser-pre-stream-vector-blocker-static.md`.

## Prompt Summary

The sub-agent was asked to critique:

- `browser_pre_stream_vector_blocker=service-window-skipped-ready-edge-plus-quarantined-preinterrupt-owner`
- The proposed patch to re-enable the before-interrupt scheduler only at the
  existing pre-first-read scheduler site.

## Loop-Guard Field

- Current field:
  `browser_pre_stream_vector_blocker=service-window-skipped-ready-edge-plus-quarantined-preinterrupt-owner`
- Code-side target:
  remove the `quarantined-preinterrupt-owner` part by restoring only the
  existing guarded scheduler owner.
- First runtime field after build/history/loop-check:
  pre-first-read scheduler timer pump before the watched read, then
  `browser_first_watch_read_ticks`.

## Findings

The sub-agent reported that this is not looping. The latest static pass changed
the boundary: the precise pre-first-read owner exists, but is unreachable
because `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` is quarantined
while the after-TB fallback is suppressed at the same ready site.

The sub-agent recommended:

- Kill more ready-edge/PFIFO-empty pump placement work.
- Kill raw pump-count fixes.
- Kill PCRTC/vblank retuning.
- Kill broad before-interrupt reactivation.
- Keep strict B6, stable ready-edge host4 baseline, native reference, and the
  first watched-read tick metric.
- Revise "before-interrupt scheduler is bad" to "the old broad
  before-interrupt owner was bad; the guarded pre-first-read owner is the only
  justified narrow path."

The proposed patch is justified, with one tightening:

```text
Use xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_ready()
instead of the raw site_ready(false) predicate.
```

That preserves existing scheduler start/accounting markers while keeping the
old broad before-interrupt path quarantined.

## Progress-Method Critique

The sub-agent said the metrics still connect to dashboard execution because the
zero-tick first watched read plausibly explains why browser reaches the XBE
execution check in the wrong state.

It also said the metrics do not yet prove visible menu or game launch, but M1
dashboard execution must pass before those later checks are meaningful.

The sub-agent called the work diagnostic-heavy, but considered this specific
static step productive because it identified a disabled owner instead of adding
another log reducer.

Process adjustment for the next 2-3 turns:

> Make one surgical patch, run only compile/build validation before the next
> required history entry, and avoid runtime until after that checkpoint.

Recommended next mode:

- Code change.
- Then build.
- Then history.
- Then loop check.

## Decision

Continue.

## Next Step

Patch `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` so it invokes only
the existing guarded pre-first-read scheduler owner. Do not restore any broad
before-interrupt pump behavior.

## Progress-Method Critique Included

Yes.
