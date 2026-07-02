# 339 - Guarded Pre-Interrupt Scheduler Build Loop Check

## Purpose

Record the required bounded sub-agent loop check after
`history/338-guarded-preinterrupt-scheduler-build.md`.

## Prompt Summary

The sub-agent was asked whether the guarded pre-first-read scheduler patch and
WASM build result justify one browser runtime.

## Loop-Guard Field

Approved next runtime field:

```text
guarded_preinterrupt_scheduler_runtime_effect
```

Specific evidence to check:

- `scheduler=pre-first-read` start/timer-pump markers before the first watched
  `0x0003a890` read.
- `pre_service_browser_first_watch_read_ticks` moves above zero.
- B4/B5/read/load/entry-ready/section-map/stream-idle/vector `0x30`/IRET and
  post-service watch-edge evidence do not regress.

## Findings

The sub-agent reported that this is not looping. The build-only step changed
code and did not yet measure runtime effect.

It recommended killing:

- Broad before-interrupt reactivation.
- More ready-edge/PFIFO/vblank placement work.
- Raw pump-count increases.
- Historical B3/B4/B5 reconfirmation.

It recommended keeping:

- Strict dashboard execution.
- Stable ready-edge host4 baseline.
- First watched-read tick metric.
- Broad-path quarantine.

It revised the scheduler hypothesis:

> Ungated before-interrupt scheduling was bad; this guarded owner deserves
> exactly one runtime measurement.

The approved runtime should be ready-edge-host4-shaped with:

```sh
XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_INTERVAL=1
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-pre-first-read-micro-scheduler
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT=4
```

It should use the rebuilt `build-wasm-pic` artifact and a fresh output
directory.

## Progress-Method Critique

The sub-agent said the current metric still connects to strict dashboard
execution because the zero-tick first watched read is the active precondition
mismatch before browser reaches the dashboard execution detector in the wrong
state.

It does not yet prove visible main menu or game launch, but M1 must be fixed
before those gates are meaningful.

The sub-agent said this step is not runtime-rerun-heavy because it measures the
first runtime effect of a guarded code change.

Process adjustment:

> Predeclare the runtime as non-repeatable unless it reaches the named field; if
> it times out early, inspect before any retry.

Recommended next mode:

- Runtime probing.

## Decision

Continue.

## Next Step

Run exactly one browser runtime for
`guarded_preinterrupt_scheduler_runtime_effect`, then run the bounded reducers
and write history before any further action.

## Progress-Method Critique Included

Yes.
