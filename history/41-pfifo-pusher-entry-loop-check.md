# PFIFO Pusher Entry Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether history/40
  justifies moving from PFIFO-window publication classification to PFIFO
  producer-entry timing, or whether that would repeat the same
  no-previous-PFIFO-publication finding.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/39, history/40, the
PFIFO_WINDOW_PUBLICATION_CLASSIFY result, and the proposed next producer-entry
comparison or diagnostic.
```

## Inputs And Artifacts

- `goal.md`
- `AGENTS.md`
- `history/39-boundary-helper-loop-check.md`
- `history/40-pfifo-window-publication-classifier.md`
- Classifier summary:
  `PFIFO_WINDOW_PUBLICATION_CLASSIFY result=pass divergence=pfifo-producer-starts-after-opportunities-window-start-gated timer_opportunities=8 pfifo_progress=128 pfifo_windows=379 window_start=0x03880e00 first_opportunity_line=1162 last_opportunity_line=1228 progress_before_first_opportunity=no last_not_published_reason_before_first_opportunity=no-pfifo-producer-before-first-opportunity first_pfifo_progress_line=1385 first_pfifo_progress_delta_from_last_opportunity=157 first_pfifo_progress_op=pusher-enter first_pfifo_progress_dma_get=0x03880000 last_not_published_reason_before_window=dma-get-before-window-start first_window_line=1884 first_published_reason=window-start-reached`
- Boundary helper summary:
  `B6_CURRENT_BOUNDARY_PFIFO_WINDOW_PUBLICATION result=pass divergence=pfifo-producer-starts-after-opportunities-window-start-gated`
- Current B6 result:
  `B6_CURRENT_BOUNDARY_RESULT result=pass reason=current-boundary-summarized b6=fail b6_reason=missing-xbe-executed-marker`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by deciding whether the next
  step should explain why browser PFIFO pusher entry starts after the
  timer-opportunity window.

## Findings

- Result: anti-loop check completed.
- Decision: `revise`.
- The sub-agent said this is not looping if the next step moves from
  PFIFO-window publication to PFIFO producer-start ordering. It becomes a loop
  only if the next action remeasures `opportunities_with_previous_pfifo=0`,
  `first_next_pfifo_line=1884`, or per-opportunity predecessor state again.
- Narrowest next fact: why the browser PFIFO pusher has no producer event
  before timer-opportunity lines `1162-1228`, while the later first producer
  starts at line `1385`.
- The exact next fields should be
  `last_pusher_not_entered_reason_before_first_opportunity` and
  `first_pusher_enter_reason`.
- Killed hypothesis: stale PFIFO-window snapshot selection.
- Kept hypothesis: browser is already behind before the shared poll because
  expired timer work cannot run through the current PFIFO-window wait gate.
- Revised hypothesis: the blocker is no longer broad PFIFO-window publication.
  It is that PFIFO producer entry starts too late, then window publication is
  gated until `dma_get=0x03880e00`.
- Better experiment: add or run a focused pusher-entry classifier using the
  current gate-split artifact if markers already exist; otherwise run one
  tightly scoped diagnostic.

## Decision

- Status: critique checkpoint
- Why: it prevents the next step from remeasuring PFIFO-window publication and
  redirects the next technical slice to PFIFO pusher-entry timing.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: explain pusher-entry absence before the
  timer-opportunity window with
  `last_pusher_not_entered_reason_before_first_opportunity` and
  `first_pusher_enter_reason`.

## Next Step

- Update the active docs so the next B6 slice is PFIFO pusher-entry timing, not
  PFIFO-window publication broadly.
- Then add or run a focused pusher-entry classifier before any broad runtime
  probe.
