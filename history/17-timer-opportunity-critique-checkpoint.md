# Timer Opportunity Critique Checkpoint

## Purpose

- One new fact this critique was supposed to produce: whether adding the bounded browser `headless=timer-opportunity` marker is still justified after the source inspection, or whether it repeats the pump-placement loop.

## Command(s)

```text
Read-only GPT-5.5/xhigh critique with:
- goal.md
- history/15-pre-stream-timer-opportunity-critique.md
- history/16-main-loop-readiness-source-inspection.md
- scripts/xbox-pre-stream-tick-source-compare.py
- scripts/xbox-b6-current-boundary.sh
```

## Inputs And Artifacts

- Current browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Current comparator field: `pre_service_browser_first_watch_read_ticks=0`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`

## Findings

- Result: continue.
- Not looping yet; the last step confirmed existing markers cannot explain the pre-stream eligibility versus gating-skip split.
- The proposed marker is justified if bounded, diagnostic-only, and run against the current ready-edge-host4 baseline only.
- The marker should explain whether browser sees an expired or eligible virtual timer opportunity before stream-idle or skips it due to readiness, wait, or interrupt state.
- Compiling existing main-loop timer observation under `CONFIG_XEMU_BROWSER_BOOT` is justified only as evidence capture, not behavior change.
- Do not rerun pump-placement, all-timers, normal-vblank, precommit, B3/B4/B5, native-reference, or visual-comparison work.

## Decision

- Status: current support
- Why: the proposed code change can explain the primary loop-guard field without weakening the B6 contract.
- Independent critique used: yes

## Next Step

- Add bounded `headless=timer-opportunity` diagnostics and browser-compiled main-loop timer observation, then run one current ready-edge-host4 diagnostic and compare pre-stream opportunity evidence.
