# Timer Opportunity Build-Run Critique Checkpoint

## Purpose

- One new fact this critique was supposed to produce: whether build-checking and running the new `headless=timer-opportunity` diagnostic avoids repeating the pump-placement loop.

## Command(s)

```text
Read-only GPT-5.5/xhigh critique of:
- goal.md
- history/17-timer-opportunity-critique-checkpoint.md
- history/18-timer-opportunity-static-selftest.md
- scripts/xbox-pre-stream-tick-source-compare.py
- scripts/xbox-pre-stream-tick-source-compare-selftest.sh
```

## Inputs And Artifacts

- Active browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Recent result: parser/static selftest passed; no C build or browser runtime run yet.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`

## Findings

- Result: continue.
- Not looping yet because the next run can add new pre-stream timer-opportunity evidence.
- The run is justified only if it uses the current ready-edge-host4 mode and reports whether browser saw expired or ready timer opportunities before stream-idle.
- The key explanatory fields are `browser_pre_stream_timer_opportunity_ready`, `browser_pre_stream_timer_opportunity_expired`, `browser_pre_stream_timer_opportunity_reasons`, and `browser_first_pre_opportunity_deadline_delta`.
- Do not rerun negative pump/vblank/precommit/all-timers modes or broaden to B3/B4/B5/native/visual work.

## Decision

- Status: current support
- Why: the proposed build-check plus one current diagnostic can explain the primary loop-guard field without weakening B6.
- Independent critique used: yes

## Next Step

- Build-check the C diagnostic changes, wire the opportunity summary into `scripts/xbox-b6-current-boundary.sh` only if needed, then run exactly one current ready-edge-host4 browser diagnostic if the build succeeds.
