# 335 - First Watch Read Gap Owner Loop Check

## Purpose

Record the required bounded sub-agent loop check after
`history/334-first-watch-read-gap-owner-helper.md`.

## Prompt Summary

The sub-agent was asked to review the new helper result:

- `FIRST_WATCH_READ_GAP_OWNER result=pass`
- `first_watch_read_tick_gap_owner=browser-lacks-native-pre-stream-vector-timer-production`
- `first_watch_read_tick_delta=136`

It was also asked to include a `Progress-Method Critique`.

## Loop-Guard Field

- Current field explained:
  `first_watch_read_tick_gap_owner=browser-lacks-native-pre-stream-vector-timer-production`
- Recommended next field:
  `browser_pre_stream_vector_blocker`

## Findings

The sub-agent reported that this turn is not looping. The new helper changes
the boundary from deciding which branch to force to proving that the browser
lacks the native pre-stream vector/timer-production phase.

It recommended killing these hypotheses:

- PCRTC final-window forcing as the main path.
- BQL/IRQ assertion alone as sufficient.
- Memory-watch address/callback artifact.
- Raw pump-count restoration.

It recommended keeping:

- The stable ready-edge host4 baseline.
- The strict B6 checker.
- The native reference.
- `browser_first_watch_read_ticks` as the active metric.

It revised the active explanation:

> The problem is not "assert one interrupt earlier"; it is "browser lacks or
> skips the native serviceable pre-stream CPU/main-loop window that produces
> PIT/vector/timer work before the watched read."

The next narrow fact should be:

```text
browser_pre_stream_vector_blocker
```

Suggested values include:

- `timer-not-dispatched`
- `irq-not-raised`
- `pic-not-ackable`
- `cpu-not-yielded`
- `interrupts-disabled`
- `service-window-skipped`

The recommended next action is a bounded code-inspection pass over:

- Browser headless timer pump.
- PFIFO stream-idle / wait-source gates.
- PIT/PCRTC IRQ delivery.
- CPU interrupt/yield path.

## Progress-Method Critique

The sub-agent said the current metrics still connect to strict dashboard
execution because the browser reaches the first watched read too early, at zero
ticks, and then misses strict `dashboard=xbe-executed`.

It also said these metrics do not prove visible main menu or game launch yet,
but they are still on the required M1 path before those later gates can be
meaningful.

The sub-agent called the work diagnostic-heavy, but considered the latest
static helper useful because it killed a branch and explained the active field.
It warned not to add another reducer unless code inspection exposes a specific
ambiguity.

Process adjustment for the next 2-3 turns:

> One bounded inspection summary should produce either a deterministic-mode
> patch target or a clear blocker; no new runtime until that patch predicts
> movement in `browser_pre_stream_timer_progress` or
> `browser_first_watch_read_ticks`.

Recommended next mode:

- Code inspection.
- Then a scoped code change if the blocker is identified.
- Not runtime probing.
- Not stopping.

## Decision

Continue.

## Next Step

Run a bounded code-inspection pass for `browser_pre_stream_vector_blocker`
before any runtime experiment. The inspection should end with either a concrete
deterministic-mode patch target or a clear blocker.

## Progress-Method Critique Included

Yes.
