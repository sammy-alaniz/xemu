# Ready-Edge All-Timers Mode Static Check

## Purpose

- One new fact this run was supposed to produce: whether an opt-in ready-edge mode can be wired to test native-like `qemu_clock_run_all_timers()` at the PFIFO stream-idle edge, while keeping the current ready-edge baseline unchanged.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh

scripts/xbox-pre-service-tick-gap-compare-selftest.sh

ninja -C build-docker-b6-pfifo-boundary

command -v ninja
command -v ninja-build
command -v make
ls -l build-docker-b6-pfifo-boundary/Makefile build-docker-b6-pfifo-boundary/build.ninja
file build-docker-b6-pfifo-boundary/Makefile build-docker-b6-pfifo-boundary/build.ninja

make -C build-docker-b6-pfifo-boundary

git diff --check
```

## Inputs And Artifacts

- Baseline native log: not consumed by this static/code verification.
- Baseline browser log: not consumed by this static/code verification.
- Output directory/log: command stdout only
- Fixture assumptions: no private fixtures used

## Expected Field(s)

- Loop-guard field(s) this change is intended to test in a later browser run: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: shell syntax check passed, pre-service comparator selftest passed, and `git diff --check` passed.
- Code change adds opt-in `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump-all`.
- The existing `pfifo-ready-edge-qemu-pump` mode remains virtual-only and bounded as before.
- The new mode emits distinct `source=browser-ready-edge-qemu-pump-all` and uses `qemu_clock_run_all_timers()` at the same PFIFO ready edge.
- Compile verification did not run locally: `ninja` and `ninja-build` are not on `PATH`; `make -C build-docker-b6-pfifo-boundary` failed because the generated `Makefile` is a broken symlink to `/workspace/Makefile`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was a static/tooling check before any browser runtime run.

## Decision

- Status: current
- Why: the mode is narrow and directly tests whether the ready-edge native/browser difference is all-clocks dispatch versus the current virtual-only single-timer dispatch.
- Independent critique used: no

## Next Step

- Narrow follow-up: run or build the browser diagnostic with `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE=pfifo-ready-edge-qemu-pump-all` and compare `pre_service_browser_first_watch_read_ticks`, preserving the current B4/B5/read/load/entry-ready/section-map/stream-idle/IRET checks.
