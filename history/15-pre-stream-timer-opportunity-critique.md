# Pre-Stream Timer Opportunity Critique

## Purpose

- One new fact this critique was supposed to produce: whether the proposed next step escapes the pump-placement loop by targeting the missing browser pre-stream timer/vector service path.

## Command(s)

```text
Spawned read-only GPT-5.5/xhigh critique sub-agent with current goal.md, latest history entries, scripts/xbox-pre-stream-tick-source-compare.py, scripts/xbox-b6-current-boundary.sh, and the current native/browser comparator commands.
```

## Inputs And Artifacts

- `goal.md`
- `history/9-pre-stream-tick-source-scout.md` through `history/13-pre-stream-timer-source-map.md`
- `scripts/xbox-pre-stream-tick-source-compare.py`
- `scripts/xbox-b6-current-boundary.sh`
- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`

## Findings

- Result: continue.
- Critique says we are not looping if the next step stays limited to the pre-stream timer-opportunity question.
- The loop would be another ready-edge/all-timers/post-stream/pump-count run; those negative controls already make that assumption stale.
- The narrowest next fact is whether browser has an eligible pre-stream PIT/main-loop timer opportunity before `pfifo=stream-idle-transition` and fails to service it, or whether browser never reaches the native-style pre-stream main-loop wait/timer path at all.
- Kill broad pump-placement/count fixes and the idea that the `0x80030e84` block arithmetic is the bug.
- Keep the strict B6 contract, ready-edge-host4 as the active browser baseline, and `0x0003a890` as the current timing diagnostic.
- Revise the boundary to missing browser pre-stream PIT/timer/vector `0x30` service before stream-idle.

## Decision

- Status: current support
- Why: the proposed next diagnostic is justified by the loop guard only if it targets the pre-stream opportunity/service split.
- Independent critique used: yes

## Next Step

- Add a bounded pre-stream timer-opportunity tracer around browser main-loop wait/timer dispatch and the PFIFO stream-idle boundary, recording PIT deadline/expired state, virtual clock delta, timer dispatch eligibility, PIC/vector `0x30` state, and whether the path was skipped.
