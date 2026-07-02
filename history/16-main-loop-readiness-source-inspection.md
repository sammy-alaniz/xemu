# Main-Loop Readiness Source Inspection

## Purpose

- One new fact this probe was supposed to produce: whether existing code can already distinguish browser pre-stream timer opportunity from readiness-gate skip, or whether a new diagnostic marker is needed.

## Command(s)

```sh
rg -n "main_loop_timer|MAIN_LOOP_TIMER|browser_diagnostic|timer_pump_ready|pump_ready|observe_main_loop_timers|xemu_xbe_main_loop_timer_source_is_browser_diagnostic" xemu-xbe.c xemu-xbe.h include hw scripts | head -n 200

sed -n '780,910p' xemu-xbe.c

sed -n '910,1010p' xemu-xbe.c

sed -n '1540,1715p' xemu-xbe.c

sed -n '4935,5015p' xemu-xbe.c

rg -n "observe_main_loop_timers\\(|qemu_clock_deadline_ns_all\\(|qemu_poll_ns\\(|main_loop_wait|os_host_main_loop_wait|emscripten" -S . --glob '!history/**' --glob '!build-real-b3-matrix/**' --glob '!build*/**' | head -n 220

rg -n "headless=timer-pump-gate|timer_pump_gate|pump-gate|observe.*gate|gate_trace" xemu-xbe.c xemu-xbe.h scripts -S

rg -n "main_loop_wait|os_host_main_loop_wait|qemu_poll_ns|qemu_clock_deadline_ns_all|qemu_clock_run_all_timers|qemu_clock_run_timers" util stubs system include -S | head -n 220

sed -n '640,725p' util/main-loop.c

sed -n '1300,1565p' xemu-xbe.c

sed -n '350,390p' ui/xemu-headless.c

sed -n '455,485p' xemu-xbe.h

sed -n '130,390p' ui/xemu-headless.c

sed -n '520,555p' ui/xemu-headless.c
```

## Inputs And Artifacts

- `xemu-xbe.c`
- `xemu-xbe.h`
- `util/main-loop.c`
- `ui/xemu-headless.c`
- Output: command stdout only; no emulation run.

## Expected Field(s)

- Loop-guard field this probe supports explaining: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: source-level evidence that a new focused diagnostic marker is needed.
- `util/main-loop.c` records `BOOT_MARK b6 main-loop=timers` only under `#ifdef XBOX`, even though browser boot diagnostics also need this evidence.
- Browser headless already emits `headless=timer-pump-gate`, but it only reports `entry_ready` and `pump_ready`; it does not include virtual timer deadline/expired state, wait state, CPU interrupt state, or a readiness reason.
- `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` currently returns only a boolean, so the caller cannot tell whether the browser skipped because of entry readiness, mode, IRQ-after-PFIFO-empty gating, ready-edge wait state, or another condition.
- The existing pre-transition gate trace is useful for older pump modes but does not answer the current ready-edge baseline question: whether there was an eligible pre-stream timer opportunity before `pfifo=stream-idle-transition`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation run was performed.

## Decision

- Status: current support
- Why: add a diagnostic-only browser timer-opportunity marker instead of changing timer behavior or rerunning pump variants.
- Independent critique used: yes

## Next Step

- Add a bounded `headless=timer-opportunity` marker with readiness reason, virtual timer state, wait state, CPU interrupt state, and transition status. Also include `CONFIG_XEMU_BROWSER_BOOT` in the main-loop timer observation compile guard where appropriate.
