# PFIFO Scheduler Marker Loop Check

## Purpose

Run the required sub-agent loop check after writing
`history/44-pfifo-scheduler-marker-diagnostic.md`.

## Command(s)

```text
Spawned GPT-5.5/xhigh critique sub-agent Gibbs
agent_id=019f191c-bbf4-7de0-ae52-fe2a95c1623e
```

## Inputs/Artifacts

- `goal.md`
- `history/42-pfifo-pusher-entry-classifier.md`
- `history/43-pfifo-pre-enter-loop-check.md`
- `history/44-pfifo-scheduler-marker-diagnostic.md`
- Current pusher-entry classifier output for the gate-split artifact
- Current scheduler classifier skip output for the old gate-split artifact

## Expected Field(s)

- `pfifo_scheduler_state_before_first_timer_opportunity`

## Findings

The critique found we are not looping because the proposed run populates a
marker absent from the old artifact instead of remeasuring PFIFO-window
publication or pusher-entry ordering. It warned that rerunning only the same
opportunity/window/pusher classifiers to reconfirm lines 1162, 1228, and 1385
would become looping.

The narrowest next fact is:

```text
pfifo_scheduler_state_before_first_timer_opportunity
```

The critique said to kill pusher-call/skip ambiguity before line 1162,
already-published PFIFO-window ignored, and generic pump/vblank/precommit fixes.
It kept the hypothesis that browser is behind because expired pre-stream timer
work is blocked before PFIFO-window/pusher progress, and revised the active
blocker to PFIFO scheduler/wake state before the opportunity window.

The proposed focused run is justified because it can change or explain
`pfifo_scheduler_state_before_first_timer_opportunity`, which in turn explains
`pre_service_browser_first_watch_read_ticks=0`.

## Decision

continue

## Next Step

Run the focused gate-split browser runtime with the new PFIFO scheduler marker,
then reduce it with `scripts/xbox-pfifo-scheduler-state-classify.py`.
