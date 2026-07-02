# Pre-Stream Timer Code Inspection

## Purpose

- One new fact this probe was supposed to produce: which exact code paths emit PIT, main-loop timer, and ready-edge timer-pump diagnostics so the next change can target pre-stream opportunity/service evidence instead of another pump variant.

## Command(s)

```sh
sed -n '430,560p' hw/xbox/nv2a/pfifo.c

sed -n '4720,4935p' xemu-xbe.c

sed -n '240,325p' hw/timer/i8254.c

sed -n '920,980p' accel/tcg/cpu-exec.c
```

## Inputs And Artifacts

- `hw/xbox/nv2a/pfifo.c`
- `xemu-xbe.c`
- `hw/timer/i8254.c`
- `accel/tcg/cpu-exec.c`
- Output: command stdout only; no emulation run.

## Expected Field(s)

- Loop-guard field this probe supports explaining: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: source inspection support.
- `hw/timer/i8254.c` calls `xemu_xbe_boot_trace_observe_pit_irq_timer()` from `pit_irq_timer_update()` before `qemu_set_irq()`.
- `xemu-xbe.c` emits `BOOT_MARK b6 pit=irq-timer` and `BOOT_MARK b6 main-loop=timers`; main-loop timer markers are gated by `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` unless the source is a browser diagnostic source.
- `hw/xbox/nv2a/pfifo.c` implements the diagnostic ready-edge pump, including `browser-ready-edge-qemu-pump` and the negative all-timers variant.
- `accel/tcg/cpu-exec.c` implements the TCG-side timer pump, which is not the active next target because the new boundary is before browser stream-idle and before the ready-edge post-service path.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation run was performed.

## Decision

- Status: current support
- Why: the next useful diagnostic should make pre-stream main-loop/timer dispatch opportunity visible, not add another post-stream timer pump.
- Independent critique used: no

## Next Step

- Add a bounded pre-stream timer-opportunity tracer that tells whether browser sees an eligible virtual timer/deadline before PFIFO stream-idle and whether that path is skipped or simply absent.
