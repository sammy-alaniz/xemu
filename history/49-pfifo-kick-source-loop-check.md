# PFIFO Kick Source Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether the
  source-tagged PFIFO scheduler runtime would be a loop or a justified next
  step.

## Command(s)

```sh
# Sub-agent: Banach / 019f192f-f6ef-7840-872c-3f91652fb288
# Model override requested: gpt-5.5
# Reasoning effort requested: xhigh
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log`
- Output directory/log: sub-agent completion in the Codex thread.
- Fixture assumptions: no fixture contents were inspected by this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `kick_sources_before_first_opportunity`,
  `first_kick_after_last_opportunity_source`.

## Findings

- Result: continue.
- Important critique lines:
  - We are not looping because history 48 added new source-tagged PFIFO kick
    markers that the old artifact could not emit.
  - The narrowest next fact is whether
    `kick_sources_before_first_opportunity` remains empty and, if so, which
    concrete call site populates `first_kick_after_last_opportunity_source`.
  - Kill the idea that untagged scheduler output is still actionable.
  - Keep the hypothesis that browser pre-service tick accumulation is blocked
    until PFIFO/window/pusher progress reaches the condition that lets expired
    timer work run.
  - Revise the active ambiguity from "did the scheduler run?" to "which source
    first kicks PFIFO after the missed timer-opportunity window, and was any
    source available before it?"
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not tested by this read-only critique.

## Decision

- Status: current
- Why: the next browser runtime has a new marker field to populate and is not a
  repeat of the scheduler/pusher boundary.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: no better experiment should precede the source-
  tagged runtime; the single field to change first is
  `first_kick_after_last_opportunity_source`.

## Next Step

- Narrow follow-up: run the focused ready-edge host4 browser runtime with the
  rebuilt source-tagged wasm, then reduce it with
  `scripts/xbox-pfifo-scheduler-state-classify.py` and
  `scripts/xbox-b6-current-boundary.sh`.
