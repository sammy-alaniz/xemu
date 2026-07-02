# Timer Opportunity Wait Snapshot Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the
  `pfifo_empty_blocker=wait-source-not-pfifo-window` result justifies targeted
  wait-snapshot inspection before another runtime probe.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/34-timer-opportunity-pfifo-empty-blocker-split.md
and the proposed stale PCRTC-vs-PFIFO wait-snapshot inspection.
```

## Inputs And Artifacts

- `goal.md`
- `history/33-timer-opportunity-gate-split-loop-check.md`
- `history/34-timer-opportunity-pfifo-empty-blocker-split.md`
- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- Comparator summary:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=pass divergence=browser-lacks-pre-stream-vector-service`
- Key fields:
  `browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`,
  `browser_first_watch_read_ticks=0`,
  `first_watch_read_tick_delta=136`.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by deciding whether the next
  action can explain why the timer-opportunity gate sees PCRTC wait state rather
  than PFIFO wait state before the first watched read.

## Findings

- Result: anti-loop check passed.
- The sub-agent said this is not looping because the latest run added the new
  discriminator `browser_pre_stream_timer_opportunity_pfifo_empty_blockers=wait-source-not-pfifo-window`.
- It said the work would become a loop if the next action were another broad
  pump/vblank/precommit variant assuming expired timers alone will advance
  ticks.
- It killed the hypothesis that browser lacks expired pre-stream timer work.
- It kept the hypothesis that browser is already behind before the first
  watched read.
- It revised the blocker from generic PFIFO emptiness to the specific fact that
  timer-opportunity sampling sees `wait_source=pcrtc` and
  `pfifo_empty_blocker=wait-source-not-pfifo-window`.
- It said docs sync plus targeted wait-snapshot inspection is justified.
- It recommended a static/log comparator over the existing gate-split artifact
  that pairs each `headless=timer-opportunity` with nearest PFIFO wait
  publication and reports whether a PFIFO-window snapshot existed but was not
  selected.

## Decision

- Status: critique checkpoint
- Decision: continue
- Why: a log/static comparator can explain `pre_service_browser_first_watch_read_ticks`
  without another runtime probe.

## Next Step

- Update `goal.md` and `AGENTS.md` to make the gate-split v1 artifact current,
  then add a static comparator over the existing gate-split log that compares
  timer-opportunity wait snapshots against nearby PFIFO wait publications.
