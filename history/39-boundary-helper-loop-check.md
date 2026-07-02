# Boundary Helper Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the
  boundary-helper timer-opportunity summary in history/38 justifies the
  proposed next step, or whether it would repeat the already-proven
  no-previous-PFIFO-publication relation.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/36, history/37, history/38, the new
B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT summary, and the proposed next
PFIFO publication-boundary step.
```

## Inputs And Artifacts

- `goal.md`
- `AGENTS.md`
- `history/36-timer-opportunity-wait-snapshot-static-compare.md`
- `history/37-timer-opportunity-publication-boundary-loop-check.md`
- `history/38-boundary-helper-timer-opportunity-wait-summary.md`
- Boundary helper summary:
  `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT result=pass divergence=no-pfifo-window-published-before-opportunities timer_opportunities=8 pfifo_window_publications=379 opportunities_with_previous_pfifo=0 opportunities_with_next_pfifo=8 opportunity_wait_sources=pcrtc opportunity_wait_ops=vblank-suppress opportunity_blockers=wait-source-not-pfifo-window opportunity_reasons=wait-not-pfifo-empty first_opportunity_line=1162 first_previous_pfifo_line=0 first_next_pfifo_line=1884 first_next_pfifo_delta=722`
- Pre-stream tick-source summary:
  `B6_CURRENT_BOUNDARY_PRE_STREAM_TICK_SOURCE result=pass divergence=browser-lacks-pre-stream-vector-service first_watch_read_tick_delta=136 native_first_watch_read_ticks=136 browser_first_watch_read_ticks=0`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by deciding whether the next
  experiment should remeasure PFIFO predecessor state or classify the producer
  path that first publishes PFIFO-window state.

## Findings

- Result: anti-loop check completed.
- Decision: `revise`.
- The sub-agent said the work is looping if the next action only instruments
  per-opportunity PFIFO predecessor state, because history/36 and history/38
  already prove `opportunities_with_previous_pfifo=0`,
  `opportunities_with_next_pfifo=8`, and first later PFIFO publication at line
  `1884`.
- Narrowest next fact: why the first PFIFO-window publication does not exist
  before timer-opportunity lines `1162-1228`; specifically, which
  producer/predicate first permits `wait_source=pfifo-window` and why that
  condition is absent at the first opportunity.
- Killed hypothesis: the timer gate is ignoring an already-published
  PFIFO-window snapshot.
- Kept hypothesis: browser is behind before the first watched read despite
  expired timer work.
- Revised hypothesis: the blocker is PFIFO-window publication ordering before
  pre-stream timer dispatch, not stale snapshot selection.
- Better experiment: instrument or statically classify the first PFIFO-window
  publication producer path, reporting the last not-published reason before line
  `1162` and the first published reason at line `1884`.

## Decision

- Status: critique checkpoint
- Why: it prevents the next step from remeasuring the same
  no-previous-PFIFO-publication fact and redirects work to the producer/predicate
  that controls publication.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: classify the first PFIFO-window publication
  producer path and report the last not-published reason before opportunity
  sampling plus the first published reason later in the log.

## Next Step

- Update `goal.md` and `AGENTS.md` so the next technical action targets the
  PFIFO-window publication producer/predicate, not another per-opportunity
  predecessor-state remeasurement.
