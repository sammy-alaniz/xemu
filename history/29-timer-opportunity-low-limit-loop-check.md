# Timer Opportunity Low-Limit Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether a lower-limit
  timer-opportunity rerun is justified after `history/28` showed 128 blocked
  pre-stream opportunities but missed the first watched read.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/28-timer-opportunity-v2-entry-ready-blocked.md
and the proposed lower-perturbation timer-opportunity follow-up.
```

## Inputs And Artifacts

- `goal.md`
- `history/27-timer-opportunity-pre-entry-loop-check.md`
- `history/28-timer-opportunity-v2-entry-ready-blocked.md`
- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-v2/browser-runtime.log`
- Comparator summary:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=fail divergence=missing-first-watch-read`
- New v2 fields:
  `browser_pre_stream_timer_opportunities=128`,
  `browser_pre_stream_timer_opportunity_ready=0`,
  `browser_pre_stream_timer_opportunity_expired=128`,
  `browser_pre_stream_timer_opportunity_reasons=wait-not-pfifo-empty`.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by confirming whether the next
  run can replace v2's missing first watched read with a concrete tick value
  while retaining the opportunity blocker reason.

## Findings

- Result: anti-loop check passed.
- The sub-agent said this is not looping because v2 produced a new fact:
  entry-ready pre-stream timer opportunities exist, are expired, and are blocked
  by `wait-not-pfifo-empty`.
- It said repeating the 128-sample marker would be looping.
- It killed the hypothesis that browser has no pre-stream expired timer
  opportunity.
- It kept the hypothesis that browser is behind before the first watched read.
- It revised the current hypothesis to: expired pre-stream timer work exists,
  but current readiness gating prevents dispatch before PFIFO stream-idle.
- It said the proposed lower-limit run is justified because it can change or
  explain `pre_service_browser_first_watch_read_ticks`.
- It recommended a summarize-only timer-opportunity marker only if the
  low-limit run still times out before first read.

## Decision

- Status: critique checkpoint
- Decision: continue
- Why: the next run is a bounded no-code perturbation reduction, not a repeat of
  the 128-sample marker.

## Next Step

- Run exactly one lower-limit ready-edge-host4 browser runtime with
  `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8` so the artifact can test
  whether the first watched read and IRET-pair evidence return while preserving
  the `wait-not-pfifo-empty` timer-opportunity signal.
