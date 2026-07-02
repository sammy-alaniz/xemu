# PFIFO DMA PUT Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether the
  source-tagged runtime in `history/50-pfifo-kick-source-runtime.md` changed the
  B6 boundary enough to justify a new next step, or whether continuing would
  loop on PFIFO scheduler/pusher evidence.

## Command(s)

```sh
# Sub-agent: Mencius / 019f1aba-5e15-7e91-adfb-2917ddd8b407
# Model override requested: gpt-5.5
# Reasoning effort requested: xhigh
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Latest browser runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- Latest combined browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log`
- Latest history entries:
  `history/49-pfifo-kick-source-loop-check.md`,
  `history/50-pfifo-kick-source-runtime.md`
- Fixture assumptions: no fixture contents were inspected by this read-only
  checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `kick_sources_before_first_opportunity`

## Findings

- Result: continue.
- Important critique lines:
  - We are not looping because the last run populated the previously missing
    field `first_kick_after_last_opportunity_source=nv-user-dma-put`.
  - It would now be looping to rerun scheduler, pusher, PFIFO-window, or
    timer-opportunity classifiers without a new question.
  - The narrowest next fact is whether the guest `NV_USER_DMA_PUT` write itself
    occurs before the expired timer-opportunity window.
  - If it does not occur before that window, the next diagnostic should record
    the first write's guest PC/edge and ordering relative to the last timer
    opportunity and first `0x0003a890` watched read.
  - Kill the hypothesis that an untagged PFIFO scheduler/pusher event is hiding
    an earlier kick.
  - Keep the hypothesis that expired timer work exists but is blocked by lack of
    PFIFO-window publication.
  - Revise the boundary from "which PFIFO kick source?" to "why does guest
    `NV_USER_DMA_PUT` publication happen only after the missed timer-opportunity
    window?"
  - Do not promote the source-tag runtime as the general CPU-flow baseline
    because it changed `browser_post_service_top_edge`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not tested by this read-only critique.

## Decision

- Status: current
- Why: the next non-looping work is no longer PFIFO scheduler source discovery;
  it is guest `NV_USER_DMA_PUT` provenance and ordering.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: update `goal.md` and `AGENTS.md` with the resolved
  `nv-user-dma-put` boundary, then add or run a focused DMA PUT
  provenance/order classifier that reports first guest DMA PUT write line,
  guest PC/edge, value, and ordering relative to timer opportunities and the
  first watched read.

## Next Step

- Narrow follow-up: update `goal.md` and `AGENTS.md` to make
  `first_kick_after_last_opportunity_source=nv-user-dma-put` the current
  resolved boundary, without making the source-tag runtime the general
  CPU-flow baseline. Then target the single field
  `kick_sources_before_first_opportunity` by classifying whether an earlier
  `NV_USER_DMA_PUT` write exists before the opportunity window.
