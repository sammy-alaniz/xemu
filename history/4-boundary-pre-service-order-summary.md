# Boundary Pre-Service Order Summary

## Purpose

- One new fact this run was supposed to produce: whether `scripts/xbox-b6-current-boundary.sh` can expose the pre-service timer/read/write/service/IRET ordering split directly without changing the existing B6 result contract.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh

scripts/xbox-b6-current-boundary.sh

scripts/xbox-pre-service-tick-gap-compare-selftest.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native memory-watch log: `build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log`
- Output directory/log: command stdout only
- Fixture assumptions: existing local B6 real fixtures and already-captured native/browser logs

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `pre_service_browser_first_watch_read_ticks` and `browser_post_service_top_edge`.

## Findings

- Result: syntax check passed, pre-service comparator selftest passed, and the boundary helper still reports `B6_CURRENT_BOUNDARY_RESULT result=pass b6=fail b6_reason=missing-xbe-executed-marker`.
- New `B6_CURRENT_BOUNDARY_PRE_SERVICE_ORDER` line reports `divergence=browser-first-watch-read-before-catchup`, `first_watch_read_tick_delta=136`, `native_first_watch_read_ticks=136`, and `browser_first_watch_read_ticks=0`.
- The new order line also reports `browser_first_timer_source=browser-ready-edge-qemu-pump`, `browser_first_timer_virtual_expired_before=yes`, `browser_first_timer_virtual_advance_ns=460032`, and `browser_first_timer_watch_ticks=0`.
- Browser first service is before the first watched read: `browser_first_service_before_read=yes`, `browser_first_service_delta_to_read=11`, `browser_first_service_eip=0x8001b030`.
- Browser first watched write is after the first watched read: `browser_first_watch_read_before_write=yes`, `browser_first_watch_write_before_read=no`, `browser_first_watch_write_delta_from_read=6`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? The boundary helper kept the same summarized baseline: B4/B5 read/load/entry-ready/section-map evidence remains represented, native execution/reference passes, browser `dashboard=xbe-executed` remains absent, and B6 remains incomplete.

## Decision

- Status: current
- Why: this makes the active blocker machine-readable and prevents future broad pump loops from being justified by vague timer-progress evidence.
- Independent critique used: no

## Next Step

- Narrow follow-up: inspect whether the browser ready-edge pump should test a native-like `qemu_clock_run_all_timers()` path instead of the current one-timer virtual-only pump, and only run it if it can change or explain `pre_service_browser_first_watch_read_ticks` without weakening the B6 contract.
