# Pre-Stream Tick Source Selftest

## Purpose

- One new fact this run was supposed to produce: whether the new pre-stream tick-source comparator has a stable synthetic contract before applying it to real B6 artifacts.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh scripts/xbox-pre-stream-tick-source-compare-selftest.sh

scripts/xbox-pre-stream-tick-source-compare-selftest.sh
```

## Inputs And Artifacts

- New comparator: `scripts/xbox-pre-stream-tick-source-compare.py`
- New selftest: `scripts/xbox-pre-stream-tick-source-compare-selftest.sh`
- Boundary helper: `scripts/xbox-b6-current-boundary.sh`
- Output: command stdout only; no real fixtures or private artifacts were read.

## Expected Field(s)

- Loop-guard field(s) this run enables explaining: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: pass.
- `bash -n` accepted the updated boundary helper and the new selftest.
- The selftest passed all three cases:
  - `browser-lacks-service`
  - `aligned`
  - `missing-transition`
- The synthetic browser-lacks-service case asserts `divergence=browser-lacks-pre-stream-vector-service`, native pre-stream vector service count `1`, browser pre-stream vector service count `0`, and first watched-read tick delta `136`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation artifacts were read or changed by this selftest.

## Decision

- Status: current support
- Why: the comparator is now safe to apply to the current B6 native/browser logs.
- Independent critique used: no

## Next Step

- Run the new comparator and the boundary helper against `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log` and `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`.
