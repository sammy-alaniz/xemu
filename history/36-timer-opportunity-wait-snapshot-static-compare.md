# Timer Opportunity Wait Snapshot Static Compare

## Purpose

- One new fact this probe was supposed to produce: whether the gate-split
  artifact had a PFIFO-window wait publication before timer-opportunity
  sampling, or whether the timer-opportunity gate only had the PCRTC snapshot
  available before the first watched read.

## Command(s)

```sh
chmod +x \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh

python3 -m py_compile scripts/xbox-timer-opportunity-wait-snapshot-compare.py
bash -n scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh
git diff --check -- \
  scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh

scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh

scripts/xbox-timer-opportunity-wait-snapshot-compare.py \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log
```

## Inputs And Artifacts

- Browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-timer-opportunity-gate-split-v1/browser-runtime.log`
- New comparator:
  `scripts/xbox-timer-opportunity-wait-snapshot-compare.py`
- New comparator selftest:
  `scripts/xbox-timer-opportunity-wait-snapshot-compare-selftest.sh`

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, by explaining why the browser
  has expired pre-stream timer opportunities but still reads the watched tick
  word at 0 ticks.
- Static split fields:
  `opportunities_with_previous_pfifo`,
  `opportunities_with_next_pfifo`, and
  `divergence`.

## Findings

- Static syntax checks passed.
- `TIMER_OPPORTUNITY_WAIT_SNAPSHOT_SELFTEST_RESULT result=pass cases=3`.
- The gate-split artifact comparator reported:
  `TIMER_OPPORTUNITY_WAIT_SNAPSHOT_COMPARE result=pass divergence=no-pfifo-window-published-before-opportunities`.
- The artifact has `timer_opportunities=8` and `pfifo_window_publications=379`.
- No timer opportunity has a previous PFIFO-window publication:
  `opportunities_with_previous_pfifo=0`.
- Every timer opportunity has a later PFIFO-window publication:
  `opportunities_with_next_pfifo=8`.
- The selected opportunity snapshot is PCRTC-only:
  `opportunity_wait_sources=pcrtc`,
  `opportunity_wait_ops=vblank-suppress`,
  `opportunity_blockers=wait-source-not-pfifo-window`,
  `opportunity_reasons=wait-not-pfifo-empty`,
  `opportunity_ready=0`,
  `opportunity_expired=8`.
- First opportunity:
  `line=1162 eip=0x8002430e wait_source=pcrtc wait_op=vblank-suppress blocker=wait-source-not-pfifo-window watch_value=0x00000000`.
- There is no previous PFIFO line for the first opportunity:
  `first_previous_pfifo_line=0`.
- The first PFIFO-window publication appears later at line 1884:
  `first_next_pfifo_delta=722`,
  `first_next_pfifo_op=pusher-new-method-inc`,
  `first_next_pfifo_dma_get=0x03880e00`,
  `first_next_pfifo_dma_put=0x03881318`,
  `first_next_pfifo_available=326`.
- Last opportunity:
  `line=1228 eip=0x80014386 wait_source=pcrtc wait_op=vblank-suppress blocker=wait-source-not-pfifo-window watch_value=0x00000000`.
- The first PFIFO-window publication is still after the last opportunity:
  `last_next_pfifo_delta=656`.

## Decision

- Status: current static diagnostic support
- Why: this rules out a stale PFIFO-window snapshot being ignored before the
  timer opportunities. At the sampled opportunity times, no PFIFO-window
  publication has happened yet; the only wait snapshot available is PCRTC
  vblank suppression.

## Next Step

- Run the required post-history sub-agent loop check.
- If approved, update `goal.md`, `AGENTS.md`, and optionally
  `scripts/xbox-b6-current-boundary.sh` so the current focused diagnostic is:
  expired pre-stream timer work exists, but PFIFO-window publication begins only
  after the timer-opportunity samples, so the next technical target is the
  earlier PFIFO wait publication/CPU scheduling boundary before the first
  watched read.
