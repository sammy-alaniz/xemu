# Timer Opportunity Limit Plumbing Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether adding explicit
  browser-side plumbing for `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT` is the
  justified next step after the host-env-only low-limit run still emitted 128
  opportunity markers.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/30-timer-opportunity-limit8-env-not-plumbed.md
and the proposed explicit browser diagnostic limit plumbing.
```

## Inputs And Artifacts

- `goal.md`
- `history/29-timer-opportunity-low-limit-loop-check.md`
- `history/30-timer-opportunity-limit8-env-not-plumbed.md`
- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-limit8-v1/browser-runtime.log`
- Comparator summary:
  `PRE_STREAM_TICK_SOURCE_COMPARE result=fail divergence=missing-first-watch-read`
- Key failed setup field:
  `browser_pre_stream_timer_opportunities=128` despite host
  `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT=8`.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by confirming whether a truly
  applied low limit can restore a concrete first watched read.
- `browser_pre_stream_timer_opportunities`, as the setup field proving the low
  limit reached the browser C-side diagnostic.

## Findings

- Result: anti-loop check passed.
- The sub-agent said this is not looping if the next step fixes plumbing first.
- It said another host-env-only low-limit run would be the loop because
  `history/30` proved that assumption false.
- It killed the hypothesis that host env alone reaches browser C-side
  diagnostics.
- It kept the finding that expired pre-stream timer opportunities exist and are
  blocked by `wait-not-pfifo-empty`.
- It revised the missing first-read interpretation: the first read may be
  missing because of 128-sample diagnostic perturbation until a real low-limit
  run proves otherwise.
- It said the proposed run is justified if the setup field
  `browser_pre_stream_timer_opportunities` drops to 8 or 16, ideally with a
  `BROWSER_DIAGNOSTIC_APPLY name=xbe_timer_opportunity_limit` line.
- It recommended treating that apply-line check as a precondition inside the
  same run.

## Decision

- Status: critique checkpoint
- Decision: continue
- Why: explicit browser plumbing is the narrow correction needed before another
  low-limit probe can answer the loop-guard field.

## Next Step

- Inspect existing browser diagnostic fixture-file plumbing, add equivalent
  plumbing for `XEMU_BOOT_TRACE_XBE_TIMER_OPPORTUNITY_LIMIT`, rebuild, and run
  exactly one low-limit ready-edge-host4 browser probe only after the log proves
  the limit was applied.
