# 194. PFIFO Source Runtime Canceled By Existing Artifact

## Purpose

Check the exact prior ready-edge host4 PFIFO scheduler-source history before
running the newly approved focused runtime, to avoid repeating a historical
diagnostic.

## Commands

```sh
sed -n '1,120p' history/50-pfifo-kick-source-runtime.md
sed -n '1,115p' history/46-pfifo-scheduler-runtime-boundary.md
rg -n "ready-edge-host4-v1|pfifo-ready-edge-qemu-pump|browser-memory-watch-write-0x3a890-ready-edge-host4" \
  history | head -80
```

## Inputs / Artifacts

- `history/50-pfifo-kick-source-runtime.md`
- `history/46-pfifo-scheduler-runtime-boundary.md`
- Prior focused runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- Prior focused combined runtime:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1-combined.log`

## Loop-Guard Field

- `first_kick_after_last_opportunity_source`

## Findings

The proposed runtime should be canceled because the selected field is already
answered by the existing focused artifact in `history/50`.

The prior focused run reports:

- `PFIFO_SCHEDULER_STATE_CLASSIFY result=pass`
- `divergence=no-pfifo-scheduler-event-before-first-opportunity`
- `scheduler_events_before_first_opportunity=0`
- `kick_events_before_first_opportunity=0`
- `kick_sources_before_first_opportunity=none`
- `first_scheduler_after_last_opportunity_line=1385`
- `first_scheduler_after_last_opportunity_op=kick`
- `first_scheduler_after_last_opportunity_kick_source=nv-user-dma-put`
- `first_kick_after_last_opportunity_source=nv-user-dma-put`
- `first_kick_after_last_opportunity_delta=130`

That means rerunning the same source-tagged PFIFO scheduler diagnostic would
violate the loop-control rule against repeating historical probes.

## Decision

Cancel the planned runtime. Treat `first_kick_after_last_opportunity_source` as
already populated with `nv-user-dma-put`.

## Next Step

Run the required bounded loop check. The next field should move past source
identification, likely into why the first `nv-user-dma-put` / PFIFO kick occurs
after the timer-opportunity window rather than before it, without rerunning the
old scheduler/pusher/window classifiers.
