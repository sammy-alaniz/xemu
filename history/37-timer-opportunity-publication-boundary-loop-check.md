# Timer Opportunity Publication Boundary Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the static
  wait-snapshot comparator justifies docs/boundary sync before any further
  runtime probe.

## Command(s)

```text
Spawned GPT-5.5/xhigh sub-agent with the bounded anti-loop prompt from
goal.md, focused on history/36-timer-opportunity-wait-snapshot-static-compare.md
and the proposed PFIFO publication-boundary docs update.
```

## Inputs And Artifacts

- `goal.md`
- `history/35-timer-opportunity-wait-snapshot-loop-check.md`
- `history/36-timer-opportunity-wait-snapshot-static-compare.md`
- Static comparator:
  `scripts/xbox-timer-opportunity-wait-snapshot-compare.py`
- Browser artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- Comparator summary:
  `TIMER_OPPORTUNITY_WAIT_SNAPSHOT_COMPARE result=pass divergence=no-pfifo-window-published-before-opportunities`
- Key fields:
  `opportunities_with_previous_pfifo=0`,
  `opportunities_with_next_pfifo=8`,
  `opportunity_wait_sources=pcrtc`,
  `opportunity_blockers=wait-source-not-pfifo-window`.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by deciding whether the next
  action should capture the refined boundary instead of running another probe.

## Findings

- Result: anti-loop check passed.
- The sub-agent said this is not looping because the latest action added a new
  discriminator: `opportunities_with_previous_pfifo=0` with
  `divergence=no-pfifo-window-published-before-opportunities`.
- It said the work would become a loop if the next action repeats
  pump/vblank/precommit variants or keeps assuming an already-published PFIFO
  snapshot is being ignored.
- It killed the hypothesis that the timer gate is ignoring an already-published
  PFIFO-window snapshot.
- It kept the hypothesis that browser is already behind before the first
  watched read despite expired pre-stream timer work.
- It revised the active hypothesis from stale PCRTC-vs-PFIFO selection to:
  PFIFO-window state is not published before the opportunity window at all.
- It approved docs/boundary sync, but not another runtime probe.
- It recommended that the next real instrumentation should publish, at each
  pre-read timer opportunity, the PFIFO wait/publication predecessor state and
  why no PFIFO-window snapshot exists yet.

## Decision

- Status: critique checkpoint
- Decision: continue
- Why: syncing docs/helper state around the new publication boundary prevents
  the next turn from repeating stale snapshot or broad timer-pump assumptions.

## Next Step

- Update `goal.md`, `AGENTS.md`, and the current-boundary helper to include the
  wait-snapshot comparator and current publication-boundary result.
