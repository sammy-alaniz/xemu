# PFIFO Pre-Enter Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether history/42
  justifies moving from inferred pusher-entry absence to explicit
  pusher-call/not-call evidence before the timer-opportunity window.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/41, history/42, the
PFIFO_PUSHER_ENTRY_CLASSIFY result, and the proposed explicit pre-enter
diagnostic or source/static proof.
```

## Inputs And Artifacts

- `goal.md`
- `AGENTS.md`
- `history/41-pfifo-pusher-entry-loop-check.md`
- `history/42-pfifo-pusher-entry-classifier.md`
- Pusher-entry classifier summary:
  `PFIFO_PUSHER_ENTRY_CLASSIFY result=pass divergence=pusher-entry-after-opportunities timer_opportunities=8 pfifo_progress=128 pusher_events=64 pusher_enter_events=6 explicit_not_entered_markers=0 first_opportunity_line=1162 last_opportunity_line=1228 previous_pusher_before_first_opportunity=no last_pusher_not_entered_source=inferred-from-absence last_pusher_not_entered_reason_before_first_opportunity=no-pusher-marker-before-first-opportunity:wait-source-pcrtc:wait-op-vblank-suppress:wait-pfifo-known-no:wait-fifo-access-no first_pusher_enter_line=1385 first_pusher_enter_delta_from_last_opportunity=157 first_pusher_enter_reason=entry-gates-open-with-dma-pending`
- Boundary helper summary:
  `B6_CURRENT_BOUNDARY_PFIFO_PUSHER_ENTRY result=pass divergence=pusher-entry-after-opportunities explicit_not_entered_markers=0 last_pusher_not_entered_source=inferred-from-absence first_pusher_enter_line=1385 first_pusher_enter_delta_from_last_opportunity=157 first_pusher_enter_reason=entry-gates-open-with-dma-pending`
- Current B6 result:
  `B6_CURRENT_BOUNDARY_RESULT result=pass reason=current-boundary-summarized b6=fail b6_reason=missing-xbe-executed-marker`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by deciding whether the next
  step should make the pre-opportunity pusher not-entered reason explicit.

## Findings

- Result: anti-loop check completed.
- Decision: `continue`.
- The sub-agent said the work is not looping if the next step only adds
  explicit pusher call/not-call evidence. It becomes a loop if the next action
  remeasures `opportunities_with_previous_pfifo=0`, PFIFO-window publication
  timing, or pusher-entry ordering without changing the inferred absence.
- Narrowest next fact: before opportunity lines `1162-1228`, was the PFIFO
  pusher never called, or was it called and skipped?
- The useful field is an explicit `last_pusher_not_entered_source/reason`, not
  another inferred value.
- Killed hypotheses: an already-published PFIFO window was ignored, and generic
  pump/vblank/count explanations.
- Kept hypothesis: browser is behind because expired pre-stream timer work is
  blocked before PFIFO-window publication.
- Revised hypothesis: the blocker is pusher scheduling/non-entry before the
  timer-opportunity window, not late PFIFO publication broadly.
- The sub-agent approved the next step only if it is a narrow source/static
  proof or diagnostic marker in the pusher/scheduler path, changing
  `last_pusher_not_entered_source` from `inferred-from-absence` to
  `not-called-before-first-opportunity` or `called-and-skipped:<reason>`.
- Better experiment: prefer source-level/static proof first if the call graph
  and existing markers can establish whether the pusher path is reachable
  before line `1162`.

## Decision

- Status: critique checkpoint
- Why: it prevents a third remeasurement of the same timer/PFIFO ordering and
  narrows the next technical step to explicit pusher call/not-call evidence.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: move to source/static proof first, then a narrow
  marker only if static proof cannot establish whether the pusher was called or
  skipped before the opportunity window.

## Next Step

- Inspect PFIFO scheduling/call sites and existing marker gates to determine
  whether source/static evidence can prove pusher was not called before
  opportunity line `1162`.
- If source/static proof is insufficient, add a narrowly gated pre-enter marker
  in the PFIFO pusher/scheduler path.
