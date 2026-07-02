# Timer Opportunity Pre-Entry Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the failed
  timer-opportunity runtime probe was a loop or a justified instrumentation
  startup failure to fix before rerunning.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/26-timer-opportunity-runtime-pre-entry-mutex-fail.md
and the proposed pre-entry timer-opportunity marker fix.
```

## Inputs And Artifacts

- `goal.md`
- `history/24-timer-opportunity-wasm-build-pass.md`
- `history/25-timer-opportunity-runtime-pre-run-critique.md`
- `history/26-timer-opportunity-runtime-pre-entry-mutex-fail.md`
- Current comparator boundary:
  `scripts/xbox-pre-stream-tick-source-compare.py` reports
  `divergence=browser-lacks-pre-stream-vector-service` and
  `first_watch_read_tick_delta=136`.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by confirming whether the next
  step can produce or explain safe entry-ready pre-stream timer-opportunity
  evidence.

## Findings

- Result: anti-loop check passed.
- The sub-agent said this is not looping because the latest failure exposed a
  new instrumentation startup bug before B3.
- It said rerunning without changing pre-entry marker behavior would be the
  loop.
- It recommended killing pre-entry timer-opportunity sampling as currently
  implemented.
- It recommended keeping the current ready-edge-host4 baseline and the
  pre-stream timer-opportunity hypothesis.
- It recommended revising the marker so it does not touch NV2A wait state, CPU
  context, or memory-watch sampling before `xemu_xbe_boot_trace_entry_ready()`
  is true.
- It said the proposed fix plus exactly one rerun is justified because it can
  explain `pre_service_browser_first_watch_read_ticks` by producing or ruling
  out entry-ready, pre-stream `headless=timer-opportunity` evidence.

## Decision

- Status: critique checkpoint
- Decision: continue
- Why: the next action is a bounded instrumentation safety fix, not another
  generic runtime rerun.

## Next Step

- Fix the timer-opportunity marker so the pre-entry path cannot lock uninitialized
  NV2A/CPU/context state, then rebuild and rerun exactly one current
  ready-edge-host4 browser runtime with the same timer-opportunity diagnostic.
