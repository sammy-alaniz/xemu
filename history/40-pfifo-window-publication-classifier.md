# PFIFO Window Publication Classifier

## Purpose

- One new fact this probe was supposed to produce: whether the first
  `pfifo=window` publication is missing before timer-opportunity sampling
  because a published snapshot is ignored, because PFIFO production has not
  started yet, or because publication is gated by the configured DMA window
  start.

## Command(s)

```sh
chmod +x \
  scripts/xbox-pfifo-window-publication-classify.py \
  scripts/xbox-pfifo-window-publication-classify-selftest.sh

bash -n \
  scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-pfifo-window-publication-classify-selftest.sh \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh \
  scripts/xbox-pre-stream-tick-source-compare-selftest.sh \
  scripts/xbox-browser-runtime-smoke.sh

python3 -m py_compile \
  scripts/xbox-pre-stream-tick-source-compare.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  scripts/xbox-pfifo-window-publication-classify.py

node --check browser/xbox-boot/worker.js
node --check browser/xbox-boot/main.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs

scripts/xbox-pfifo-window-publication-classify-selftest.sh
scripts/xbox-pre-stream-tick-source-compare-selftest.sh
scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh

git diff --check -- \
  AGENTS.md \
  goal.md \
  scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-pfifo-window-publication-classify.py \
  scripts/xbox-pfifo-window-publication-classify-selftest.sh \
  scripts/xbox-pre-stream-tick-source-compare.py \
  scripts/xbox-pre-stream-tick-source-compare-selftest.sh \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh \
  browser/xbox-boot/worker.js \
  browser/xbox-boot/main.js \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  scripts/xbox-browser-runtime-smoke.sh \
  xemu-xbe.c \
  xemu-xbe.h \
  ui/xemu-headless.c \
  util/main-loop.c

scripts/xbox-pfifo-window-publication-classify.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Timer-opportunity browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- New static classifier:
  `scripts/xbox-pfifo-window-publication-classify.py`
- New selftest:
  `scripts/xbox-pfifo-window-publication-classify-selftest.sh`
- Updated helper:
  `scripts/xbox-b6-current-boundary.sh`
- Fixture assumptions: no emulator run was started and no private fixture bytes
  were inspected; this was a static read of existing logs plus script
  validation.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by explaining the missing
  pre-opportunity PFIFO-window predecessor state without rerunning a broad
  runtime probe.
- Static fields:
  `PFIFO_WINDOW_PUBLICATION_CLASSIFY`,
  `B6_CURRENT_BOUNDARY_PFIFO_WINDOW_PUBLICATION`,
  `progress_before_first_opportunity`,
  `last_not_published_reason_before_first_opportunity`,
  `first_pfifo_progress_line`,
  `last_not_published_reason_before_window`, and
  `first_published_reason`.

## Findings

- Shell, Python, Node, and whitespace checks passed.
- `PFIFO_WINDOW_PUBLICATION_CLASSIFY_SELFTEST_RESULT result=pass cases=3`.
- `PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST_RESULT result=pass cases=3`.
- `TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST_RESULT result=pass cases=3`.
- Direct classifier output:
  `PFIFO_WINDOW_PUBLICATION_CLASSIFY result=pass divergence=pfifo-producer-starts-after-opportunities-window-start-gated timer_opportunities=8 pfifo_progress=128 pfifo_windows=379 window_start=0x03880e00 first_opportunity_line=1162 last_opportunity_line=1228 progress_before_first_opportunity=no last_not_published_before_first_opportunity_line=0 last_not_published_reason_before_first_opportunity=no-pfifo-producer-before-first-opportunity first_pfifo_progress_line=1385 first_pfifo_progress_delta_from_first_opportunity=223 first_pfifo_progress_delta_from_last_opportunity=157 first_pfifo_progress_after_first_opportunity=yes first_pfifo_progress_after_last_opportunity=yes first_pfifo_progress_op=pusher-enter first_pfifo_progress_dma_get=0x03880000 first_pfifo_progress_dma_put=0x03881300 first_pfifo_progress_available=0 progress_between_last_opportunity_and_first_window=128 last_progress_before_window_line=1594 last_progress_before_window_delta=290 last_progress_before_window_op=puller-method last_progress_before_window_dma_get=0x03880148 last_progress_before_window_dma_put=0x03881318 last_progress_before_window_available=16 last_not_published_reason_before_window=dma-get-before-window-start first_window_line=1884 first_window_delta_from_last_progress=290 first_window_op=pusher-new-method-inc first_window_dma_get=0x03880e00 first_window_dma_put=0x03881318 first_window_available=326 first_published_reason=window-start-reached`.
- Boundary helper now emits the same classifier summary:
  `B6_CURRENT_BOUNDARY_PFIFO_WINDOW_PUBLICATION result=pass divergence=pfifo-producer-starts-after-opportunities-window-start-gated pfifo_progress=128 pfifo_windows=379 window_start=0x03880e00 first_opportunity_line=1162 last_opportunity_line=1228 progress_before_first_opportunity=no last_not_published_reason_before_first_opportunity=no-pfifo-producer-before-first-opportunity first_pfifo_progress_line=1385 first_pfifo_progress_delta_from_last_opportunity=157 first_pfifo_progress_op=pusher-enter first_pfifo_progress_dma_get=0x03880000 progress_between_last_opportunity_and_first_window=128 last_progress_before_window_line=1594 last_progress_before_window_op=puller-method last_progress_before_window_dma_get=0x03880148 last_not_published_reason_before_window=dma-get-before-window-start first_window_line=1884 first_window_delta_from_last_progress=290 first_window_op=pusher-new-method-inc first_window_dma_get=0x03880e00 first_published_reason=window-start-reached`.
- The earlier timer-opportunity wait summary still holds:
  `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT result=pass divergence=no-pfifo-window-published-before-opportunities`, with
  `opportunities_with_previous_pfifo=0`,
  `opportunities_with_next_pfifo=8`, and `first_next_pfifo_line=1884`.
- B6 did not pass. The strict boundary still reports
  `B6_CURRENT_BOUNDARY_RESULT result=pass reason=current-boundary-summarized b6=fail b6_reason=missing-xbe-executed-marker`.
- B4/B5/read/load/entry-ready/section-map/stream-idle/vector-service/IRET
  evidence did not regress in the baseline summary.

## Decision

- Status: current static diagnostic support
- Why: the classifier kills the stale-snapshot hypothesis for this artifact.
  The timer opportunities happen before any PFIFO producer marker, and the later
  `pfifo=window` publication is additionally gated until `dma_get` reaches the
  configured `0x03880e00` window start.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history/39 required classifying the producer and
  first-published predicate instead of remeasuring per-opportunity predecessor
  state.

## Next Step

- Run the required post-history sub-agent loop check before any next
  experiment, run, probe, or code change.
- If approved, target why PFIFO production itself starts only after the
  timer-opportunity window, or compare native/browser PFIFO producer start
  timing relative to timer opportunities and the first watched read.
