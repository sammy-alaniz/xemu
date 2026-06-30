# Pre-Service Tick Gap Timer Order

## Purpose

- One new fact this run was supposed to produce: whether the browser first watched read of physical `0x0003a890` is explained by timer ordering, watch write ordering, or a missing service edge.

## Command(s)

```sh
scripts/xbox-pre-service-tick-gap-compare-selftest.sh

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: comparator stdout only
- Fixture assumptions: existing local B6 real fixtures and already-captured native/browser logs

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `first_watch_read_tick_delta`, `browser_first_timer_*`, `browser_first_watch_read_*`, `browser_first_watch_write_*`, and `browser_first_service_*`.

## Findings

- Result: comparator passed as a diagnostic, but still reported `divergence=browser-first-watch-read-before-catchup`.
- The first watched-read tick delta remains `136`: native reads the watched value at tick `136`, while browser reads it at tick `0`.
- Native first timer advance appears before the watched read with `virtual_expired_before=no` and `virtual_advance_ns=1163338`.
- Browser first timer advance also appears before the watched read, but the browser virtual timer is already expired with `virtual_deadline_before=0`, `virtual_expired_before=yes`, and `virtual_advance_ns=460032`.
- Browser service happens before the first watched read, but the first watched write still happens after that read.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested by this comparator run; this was an ordering diagnostic over existing B6 logs.

## Decision

- Status: current
- Why: this narrows the active B6 boundary from generic timer progress to the exact service/read/write ordering around the watched tick word.
- Independent critique used: no

## Next Step

- Narrow follow-up: inspect why the browser service/return path reaches the first watched read before the watched word is written, and only try a scheduling change if it can move the first browser read from tick `0` toward the native tick `136` without regressing B4/B5/read/load/entry-ready/section-map/stream-idle/IRET evidence.
