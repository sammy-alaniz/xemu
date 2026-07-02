# PFIFO Scheduler Marker Diagnostic

## Purpose

Add the narrow diagnostic needed to explain
`pfifo_scheduler_state_before_first_timer_opportunity`: whether the PFIFO thread
is asleep, unwoken, halted, or otherwise outside `pfifo_run_pusher` before the
first browser timer opportunity at line 1162.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh scripts/xbox-pfifo-scheduler-state-classify-selftest.sh scripts/xbox-pfifo-pusher-entry-classify-selftest.sh
python3 -m py_compile scripts/xbox-pfifo-scheduler-state-classify.py scripts/xbox-pfifo-pusher-entry-classify.py
scripts/xbox-pfifo-scheduler-state-classify-selftest.sh
scripts/xbox-pfifo-scheduler-state-classify.py --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
scripts/xbox-pfifo-pusher-entry-classify-selftest.sh
scripts/xbox-pfifo-pusher-entry-classify.py --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
scripts/xbox-b6-current-boundary.sh
git diff --check -- AGENTS.md goal.md hw/xbox/nv2a/pfifo.c scripts/xbox-b6-current-boundary.sh scripts/xbox-pfifo-scheduler-state-classify.py scripts/xbox-pfifo-scheduler-state-classify-selftest.sh
```

Attempted host C syntax proof:

```sh
cc -fsyntax-only ../hw/xbox/nv2a/pfifo.c
```

The host syntax proof could not run to the changed code because this shell lacks
the configured build's `glib.h` dependency and has no `ninja` binary. The
configured compile commands are container-oriented and reference `/workspace`,
which is not present in this host shell.

## Inputs/Artifacts

- `hw/xbox/nv2a/pfifo.c`
- `scripts/xbox-pfifo-scheduler-state-classify.py`
- `scripts/xbox-pfifo-scheduler-state-classify-selftest.sh`
- `scripts/xbox-b6-current-boundary.sh`
- `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- `goal.md`
- `AGENTS.md`

## Expected Field(s)

- `pfifo_scheduler_state_before_first_timer_opportunity`
- `B6_CURRENT_BOUNDARY_PFIFO_SCHEDULER_STATE`

## Findings

Added diagnostic-only `BOOT_MARK b6 pfifo=scheduler ...` markers at PFIFO kick,
thread-loop, kick-cleared, after-pgraph-pending, before/after-run-pusher,
skip-halt, after-pgraph-reports, idle-wait-before, idle-wait-after, and
skip-wait-kicked sites. The marker is bounded by
`XEMU_BOOT_TRACE_NV2A_PFIFO_SCHEDULER_LIMIT` with a compiled default limit of
128 and only emits after `dashboard=xbe-loaded`.

Added `scripts/xbox-pfifo-scheduler-state-classify.py`, its selftest, and
`scripts/xbox-b6-current-boundary.sh` integration.

Selftest result:

```text
PFIFO_SCHEDULER_STATE_CLASSIFY_SELFTEST_RESULT result=pass cases=3
```

Against the old gate-split artifact, the new reducer correctly reports a skip
because that log predates the scheduler marker:

```text
PFIFO_SCHEDULER_STATE_CLASSIFY result=skip divergence=missing-pfifo-scheduler-markers loop_guard_field=pfifo_scheduler_state_before_first_timer_opportunity first_opportunity_line=1162 last_opportunity_line=1228 first_pusher_enter_line=1385 scheduler_markers_present=no
```

The existing pusher-entry boundary is preserved:

```text
PFIFO_PUSHER_ENTRY_CLASSIFY result=pass divergence=pusher-entry-after-opportunities xbe_loaded_line=1015 entry_ready_line=1134 marker_contract=pusher-skip-or-enter-after-xbe-loaded first_opportunity_line=1162 last_opportunity_line=1228 last_pusher_not_entered_source=static-marker-contract last_pusher_not_entered_reason_before_first_opportunity=not-called-before-first-opportunity first_pusher_enter_line=1385 first_pusher_enter_reason=entry-gates-open-with-dma-pending first_pusher_enter_dma_to_put=4864
```

The boundary helper now emits:

```text
B6_CURRENT_BOUNDARY_PFIFO_SCHEDULER_STATE result=skip divergence=missing-pfifo-scheduler-markers loop_guard_field=pfifo_scheduler_state_before_first_timer_opportunity scheduler_markers_present=no timer_opportunity_log=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
```

## Decision

Current diagnostic reducer is ready. The old gate-split log is still useful but
cannot answer the scheduler field because it lacks the new marker. This does not
change the B6 evidence contract and does not satisfy B6.

## Next Step

Run the focused gate-split browser runtime with the rebuilt PFIFO scheduler
marker, then reduce the new log with
`scripts/xbox-pfifo-scheduler-state-classify.py`. The next result should
distinguish `pfifo-thread-asleep-before-first-opportunity`,
`pfifo-kick-before-opportunity-without-thread-wake`,
`pfifo-thread-halted-before-first-opportunity`,
`no-pfifo-scheduler-event-before-first-opportunity`, or
`pusher-call-before-first-opportunity`.
