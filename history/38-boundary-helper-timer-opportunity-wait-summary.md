# Boundary Helper Timer Opportunity Wait Summary

## Purpose

- One new fact this probe was supposed to produce: whether the standard
  read-only B6 boundary helper now surfaces the timer-opportunity wait-snapshot
  result, especially `opportunities_with_previous_pfifo=0` and the later PFIFO
  publication line, without starting emulation.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh \
  scripts/xbox-pre-stream-tick-source-compare-selftest.sh \
  scripts/xbox-browser-runtime-smoke.sh

python3 -m py_compile \
  scripts/xbox-pre-stream-tick-source-compare.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py

node --check browser/xbox-boot/worker.js
node --check browser/xbox-boot/main.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs

scripts/xbox-pre-stream-tick-source-compare-selftest.sh
scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh

git diff --check -- \
  AGENTS.md \
  goal.md \
  scripts/xbox-b6-current-boundary.sh \
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

scripts/xbox-b6-current-boundary.sh \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --timer-opportunity-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Timer-opportunity browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- Static helper:
  `scripts/xbox-b6-current-boundary.sh`
- Fixture assumptions: no emulation started and no private fixture contents were
  inspected; this was a static read of existing logs.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by making the current
  publication-boundary explanation visible in the standard helper output.
- Static summary fields:
  `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT`,
  `opportunities_with_previous_pfifo`,
  `opportunities_with_next_pfifo`, and `first_next_pfifo_line`.

## Findings

- Shell, Python, Node, and whitespace checks passed.
- `PRE_STREAM_TICK_SOURCE_COMPARE_SELFTEST_RESULT result=pass cases=3`.
- `TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST_RESULT result=pass cases=3`.
- The boundary helper completed with
  `B6_CURRENT_BOUNDARY_RESULT result=pass reason=current-boundary-summarized b6=fail b6_reason=missing-xbe-executed-marker`.
- The new helper summary line is present:
  `B6_CURRENT_BOUNDARY_TIMER_OPPORTUNITY_WAIT result=pass divergence=no-pfifo-window-published-before-opportunities`.
- Key timer-opportunity fields:
  `timer_opportunities=8`,
  `pfifo_window_publications=379`,
  `opportunities_with_previous_pfifo=0`,
  `opportunities_with_next_pfifo=8`,
  `opportunity_wait_sources=pcrtc`,
  `opportunity_wait_ops=vblank-suppress`,
  `opportunity_blockers=wait-source-not-pfifo-window`,
  `opportunity_reasons=wait-not-pfifo-empty`,
  `first_opportunity_line=1162`,
  `first_previous_pfifo_line=0`,
  `first_next_pfifo_line=1884`,
  and `first_next_pfifo_delta=722`.
- The pre-stream tick-source boundary is unchanged:
  `B6_CURRENT_BOUNDARY_PRE_STREAM_TICK_SOURCE result=pass divergence=browser-lacks-pre-stream-vector-service`,
  native first watched read is 136 ticks, browser first watched read is 0
  ticks, native has pre-stream PIT/timer/PIC/service/IRET activity, and browser
  has zeros for those same pre-stream fields.
- B6 did not pass. The strict checker still fails because browser-runtime
  `dashboard=xbe-executed` is missing.
- B4/B5/read/load/entry-ready/section-map/stream-idle/post-service comparator
  coverage did not regress in the baseline summary.

## Decision

- Status: current static diagnostic support
- Why: the standard boundary helper now exposes the publication-boundary result
  directly, so future work does not need to rediscover that expired pre-stream
  timer opportunities happen before any PFIFO-window publication.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history/37 approved docs/helper sync and rejected
  another broad runtime probe.

## Next Step

- Run the required post-history sub-agent loop check.
- If approved, make the next technical step target why PFIFO-window publication
  starts only after the timer-opportunity window, or instrument each pre-read
  timer opportunity with its PFIFO wait/publication predecessor state.
