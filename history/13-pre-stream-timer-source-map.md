# Pre-Stream Timer Source Map

## Purpose

- One new fact this probe was supposed to produce: where the current browser/native timer, PIT, and headless pump diagnostics are implemented, so the next B6 slice can target pre-stream timer service instead of rerunning ready-edge/post-stream pump modes.

## Command(s)

```sh
git status -sb

git diff --stat

rg -n "HEADLESS_TIMER|headless.*pump|main-loop=timers|timer_progress|qemu_clock_run_all_timers|qemu_clock_run_timers|browser-ready-edge|browser-headless-host-pump|pfifo-ready-edge|pcrtc-before-stream|XEMU_BROWSER_BOOT_HEADLESS" -S .

rg -n "BOOT_MARK b6 pit=irq-timer|pit=irq-timer|XBE_PIT|PIT_IRQ|pit_irq|irq-timer|main-loop=timers" -S hw include scripts xemu-xbe.c xemu-xbe.h
```

## Inputs And Artifacts

- Current worktree with uncommitted pre-stream comparator changes.
- Source files under `hw/`, `include/`, `scripts/`, `xemu-xbe.c`, and `xemu-xbe.h`.
- Output: command stdout only; no emulation run.

## Expected Field(s)

- Loop-guard field this probe supports explaining: `pre_service_browser_first_watch_read_ticks`, through the missing browser pre-stream PIT/main-loop/vector service path.

## Findings

- Result: source-map support.
- The current uncommitted worktree contains the expected pre-stream comparator/docs changes: `goal.md`, `scripts/xbox-b6-current-boundary.sh`, new comparator/selftest files, and history entries.
- PIT IRQ marker emission is in `xemu-xbe.c` via `xemu_xbe_boot_trace_observe_pit_irq_timer`, called from `hw/timer/i8254.c`.
- Main-loop timer marker emission is in `xemu-xbe.c` via `main-loop=timers`.
- Browser ready-edge pump logic is in `hw/xbox/nv2a/pfifo.c`, including `browser-ready-edge-qemu-pump` and the negative `browser-ready-edge-qemu-pump-all` mode.
- Browser runtime smoke scripts pass `XEMU_BOOT_TRACE_XBE_PIT_IRQ_LIMIT` and `XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_*` through the browser page/worker path.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation run was performed.

## Decision

- Status: current support
- Why: the next implementation should inspect or instrument the browser pre-stream timer service path around `i8254`, `xemu-xbe.c`, and the browser headless pump gates, not rerun current negative pump modes.
- Independent critique used: no

## Next Step

- Add a focused diagnostic or comparator that distinguishes "browser has a pre-stream timer opportunity but does not service it" from "browser never reaches a native-style pre-stream main-loop wait/timer path before PFIFO stream-idle."
