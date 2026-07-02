# PFIFO Pusher Entry Classifier

## Purpose

- One new fact this probe was supposed to produce: whether existing
  timer-opportunity and PFIFO progress markers can explain the missing
  pre-opportunity PFIFO producer state by naming
  `last_pusher_not_entered_reason_before_first_opportunity` and
  `first_pusher_enter_reason`.

## Command(s)

```sh
chmod +x \
  scripts/xbox-pfifo-pusher-entry-classify.py \
  scripts/xbox-pfifo-pusher-entry-classify-selftest.sh

bash -n \
  scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-pfifo-pusher-entry-classify-selftest.sh \
  scripts/xbox-pfifo-window-publication-classify-selftest.sh \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh \
  scripts/xbox-pre-stream-tick-source-compare-selftest.sh

python3 -m py_compile \
  scripts/xbox-pfifo-pusher-entry-classify.py \
  scripts/xbox-pfifo-window-publication-classify.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  scripts/xbox-pre-stream-tick-source-compare.py

scripts/xbox-pfifo-pusher-entry-classify-selftest.sh

scripts/xbox-pfifo-pusher-entry-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

git diff --check -- \
  AGENTS.md \
  goal.md \
  scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-pfifo-pusher-entry-classify.py \
  scripts/xbox-pfifo-pusher-entry-classify-selftest.sh
```

## Inputs And Artifacts

- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Timer-opportunity browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- New static classifier:
  `scripts/xbox-pfifo-pusher-entry-classify.py`
- New selftest:
  `scripts/xbox-pfifo-pusher-entry-classify-selftest.sh`
- Updated helper:
  `scripts/xbox-b6-current-boundary.sh`
- Fixture assumptions: no emulator run was started and no private fixture bytes
  were inspected; this was a static read of existing logs plus script
  validation.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by explaining why the browser
  remains at 0 ticks before the first watched read.
- Static fields:
  `PFIFO_PUSHER_ENTRY_CLASSIFY`,
  `B6_CURRENT_BOUNDARY_PFIFO_PUSHER_ENTRY`,
  `last_pusher_not_entered_reason_before_first_opportunity`,
  `last_pusher_not_entered_source`, and `first_pusher_enter_reason`.

## Findings

- Shell, Python, and whitespace checks passed.
- `PFIFO_PUSHER_ENTRY_CLASSIFY_SELFTEST_RESULT result=pass cases=3`.
- Direct classifier output:
  `PFIFO_PUSHER_ENTRY_CLASSIFY result=pass divergence=pusher-entry-after-opportunities timer_opportunities=8 pfifo_progress=128 pusher_events=64 pusher_enter_events=6 explicit_not_entered_markers=0 first_opportunity_line=1162 last_opportunity_line=1228 first_opportunity_wait_source=pcrtc first_opportunity_wait_op=vblank-suppress first_opportunity_wait_pfifo_known=no first_opportunity_wait_fifo_access=no first_opportunity_wait_dma_get=0x03880000 first_opportunity_wait_dma_put=0x03880000 previous_pusher_before_first_opportunity=no last_pusher_not_entered_source=inferred-from-absence last_pusher_not_entered_reason_before_first_opportunity=no-pusher-marker-before-first-opportunity:wait-source-pcrtc:wait-op-vblank-suppress:wait-pfifo-known-no:wait-fifo-access-no first_pusher_enter_line=1385 first_pusher_enter_delta_from_first_opportunity=223 first_pusher_enter_delta_from_last_opportunity=157 first_pusher_enter_reason=entry-gates-open-with-dma-pending first_pusher_enter_dma_get=0x03880000 first_pusher_enter_dma_put=0x03881300 first_pusher_enter_dma_to_put=4864 first_pusher_enter_pending_dma=yes first_pusher_enter_push_access=yes first_pusher_enter_dma_push_access=yes first_pusher_enter_dma_push_status=no first_pusher_enter_fifo_access=yes first_pusher_enter_waiting_flip=no first_pusher_enter_waiting_nop=no first_pusher_enter_waiting_context=no`.
- Boundary helper now emits:
  `B6_CURRENT_BOUNDARY_PFIFO_PUSHER_ENTRY result=pass divergence=pusher-entry-after-opportunities timer_opportunities=8 pfifo_progress=128 pusher_events=64 pusher_enter_events=6 explicit_not_entered_markers=0 first_opportunity_line=1162 last_opportunity_line=1228 first_opportunity_wait_source=pcrtc first_opportunity_wait_op=vblank-suppress first_opportunity_wait_pfifo_known=no first_opportunity_wait_fifo_access=no previous_pusher_before_first_opportunity=no last_pusher_not_entered_source=inferred-from-absence last_pusher_not_entered_reason_before_first_opportunity=no-pusher-marker-before-first-opportunity:wait-source-pcrtc:wait-op-vblank-suppress:wait-pfifo-known-no:wait-fifo-access-no first_pusher_enter_line=1385 first_pusher_enter_delta_from_last_opportunity=157 first_pusher_enter_reason=entry-gates-open-with-dma-pending first_pusher_enter_dma_get=0x03880000 first_pusher_enter_dma_put=0x03881300 first_pusher_enter_dma_to_put=4864 first_pusher_enter_pending_dma=yes first_pusher_enter_push_access=yes first_pusher_enter_dma_push_access=yes first_pusher_enter_dma_push_status=no first_pusher_enter_fifo_access=yes first_pusher_enter_waiting_flip=no first_pusher_enter_waiting_nop=no first_pusher_enter_waiting_context=no`.
- The classifier proves the current artifact has no pusher marker before the
  opportunity window and that first pusher entry has all entry gates open with
  pending DMA. It does not prove an explicit no-enter reason because
  `explicit_not_entered_markers=0`; the not-entered reason is inferred from
  absence plus the first timer opportunity wait snapshot.
- The earlier static facts still hold:
  `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT result=pass divergence=no-pfifo-window-published-before-opportunities`,
  `opportunities_with_previous_pfifo=0`,
  `opportunities_with_next_pfifo=8`, and
  `B6_CURRENT_BOUNDARY_PFIFO_WINDOW_PUBLICATION result=pass divergence=pfifo-producer-starts-after-opportunities-window-start-gated`.
- B6 did not pass. The strict boundary still reports
  `B6_CURRENT_BOUNDARY_RESULT result=pass reason=current-boundary-summarized b6=fail b6_reason=missing-xbe-executed-marker`.

## Decision

- Status: current static diagnostic support
- Why: this moves the boundary from PFIFO-window publication to pusher-entry
  scheduling. The current log can explain first entry readiness, but it cannot
  yet distinguish whether the pusher was not called before the opportunity
  window or was called and skipped before any `pfifo=progress` marker.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history/41 required a focused pusher-entry
  classifier before any broad runtime probe.

## Next Step

- Run the required post-history sub-agent loop check before any next
  experiment, run, probe, or code change.
- If approved, add an explicit pre-enter/not-entered PFIFO diagnostic or prove
  by another narrow static source that the pusher was not called before the
  timer-opportunity window.
