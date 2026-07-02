# First Watch Read Ticks Static Inspection

## Purpose

- One new fact this inspection was supposed to produce: identify one existing timer/order hook that could move `browser_first_watch_read_ticks` from `0` to `>0` before `0x80014f32->0x80030e84`.

## Command(s)

```sh
rg -n "deterministic|HEADLESS_TIMER_PUMP|headless=timer-pump|browser-ready-edge|browser-headless-host-pump|timer-pump-step|pump_ready|main_loop_timer_pump|qemu_clock_run_timers|timerlist_run_timers|xemu_boot_trace_tcg_timer_pump|xemu_xbe_boot_trace_tcg_timer" xemu-xbe.c ui/xemu-headless.c util/main-loop.c system/vl.c accel/tcg/cpu-exec.c browser/xbox-boot/worker.js scripts/xbox-browser-runtime-smoke.sh
nl -ba ui/xemu-headless.c | sed -n '1,260p'
nl -ba xemu-xbe.c | sed -n '900,1080p'
nl -ba xemu-xbe.c | sed -n '5000,5225p'
nl -ba ui/xemu-headless.c | sed -n '300,820p'
nl -ba accel/tcg/cpu-exec.c | sed -n '960,1030p'
nl -ba xemu-xbe.c | sed -n '1080,1260p'
nl -ba util/main-loop.c | sed -n '520,650p'
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log`
- Fixture assumptions: static read only; no runtime or build state changes.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain: `browser_first_watch_read_ticks`.

## Findings

- Result: the narrowest existing lever is the browser headless timer pump loop in `ui/xemu-headless.c`.
- `xemu_headless_pump_browser_timers()` already runs one or more `qemu_clock_run_timers_with_attrs_limit(QEMU_CLOCK_VIRTUAL, 0, 0, 1)` steps per pump.
- The number of steps is controlled by `deterministic_step_limit`, but today it only reads `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS` when full `XEMU_BROWSER_BOOT_DETERMINISTIC=1` mode is enabled.
- Full deterministic mode is not the right next move because earlier history showed it can block before `entry_ready`.
- The ready-edge host pump path already reaches the right boundary and preserves the useful gates, but one timer step can leave the watched word at 0 before the first read.
- A minimal behavioral change is to allow the ready-edge host pump to use the existing step-count setting while keeping deterministic mode off. This lets a single pump drain multiple expired timer callbacks before CPU resumes into `0x80014f32->0x80030e84`.
- The existing browser runtime plumbing already forwards `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS`, so the run command can set that field without adding new browser fixture plumbing.

## Decision

- Status: current
- Why: this targets `browser_first_watch_read_ticks` directly and avoids more edge-decision schema work.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then patch `ui/xemu-headless.c` so non-deterministic ready-edge host pumping can honor the existing timer-step count.
