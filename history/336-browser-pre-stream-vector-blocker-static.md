# 336 - Browser Pre-Stream Vector Blocker Static Inspection

## Purpose

Run the bounded code-inspection pass recommended by
`history/335-first-watch-read-gap-owner-loop-check.md`.

The named field for this pass is:

```text
browser_pre_stream_vector_blocker
```

## Commands

```sh
rg -n "browser.*headless|HEADLESS_TIMER|timer-pump|main_loop_timer|xemu_xbe_boot_trace_main_loop_timer|pump_ready|pfifo-ready|ready-edge|prestream|deterministic|PCRTC|pcrtc" \
  ui/xemu-headless.c util/main-loop.c xemu-xbe.c xemu-xbe.h \
  scripts/xbox-browser-runtime-smoke.sh browser/xbox-boot/main.js browser/xbox-boot/worker.js
```

```sh
rg -n "stream-idle|pusher-empty|pfifo|dma_get|dma_put|wait-source|wait_source|window" \
  hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/nv2a.c hw/xbox/nv2a/nv2a_int.h xemu-xbe.c
```

```sh
rg -n "cpu_handle_interrupt|x86_cpu_pending_interrupt|x86_cpu_exec_interrupt|CPU_INTERRUPT_HARD|cpu_interrupt|cpu_reset_interrupt|pic_irq_request|pic_read_irq|do_interrupt_x86_hardirq|HF_INHIBIT|IF_MASK|GIF" \
  accel target hw/i386 include system util xemu-xbe.c
```

Focused reads:

```sh
sed -n '640,850p' ui/xemu-headless.c
sed -n '930,1235p' xemu-xbe.c
sed -n '1680,2295p' xemu-xbe.c
sed -n '2735,2815p' xemu-xbe.c
sed -n '608,660p' hw/xbox/nv2a/pfifo.c
sed -n '1207,1222p' accel/tcg/cpu-exec.c
sed -n '9853,9890p' target/i386/cpu.c
sed -n '2475,2525p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Line-anchor reads:

```sh
nl -ba xemu-xbe.c | sed -n '1062,1145p'
nl -ba xemu-xbe.c | sed -n '2109,2210p'
nl -ba xemu-xbe.c | sed -n '2771,2785p'
nl -ba accel/tcg/cpu-exec.c | sed -n '1207,1222p'
nl -ba hw/xbox/nv2a/pfifo.c | sed -n '608,660p'
nl -ba target/i386/cpu.c | sed -n '9868,9883p'
```

## Inputs / Artifacts

- Code:
  - `xemu-xbe.c`
  - `accel/tcg/cpu-exec.c`
  - `hw/xbox/nv2a/pfifo.c`
  - `ui/xemu-headless.c`
  - `target/i386/cpu.c`
- Browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Prior helper result:
  `history/334-first-watch-read-gap-owner-helper.md`

## Loop-Guard Field

```text
browser_pre_stream_vector_blocker=service-window-skipped-ready-edge-plus-quarantined-preinterrupt-owner
```

## Findings

The active ready-edge browser baseline cannot create native-like pre-stream
timer/vector production because it is deliberately gated until PFIFO empty:

- `xemu_xbe_boot_trace_main_loop_timer_pump_ready()` returns ready for the
  ready-edge mode only when the wait snapshot is `pfifo-window/pusher-empty`
  (`xemu-xbe.c:1136`).
- `pfifo_boot_trace_ready_edge_timer_pump()` is one-shot and runs at the PFIFO
  stream-idle edge (`hw/xbox/nv2a/pfifo.c:608`).

The browser log matches that code shape:

- PFIFO stream-idle happens with CPU at the low idle path
  `0x8001b02f/0x8001b030`, not at the native high pre-first-read path.
- The ready-edge timer pump sets `CPU_INTERRUPT_HARD` while IRQ delivery is
  inhibited at `0x8001b02f`.
- Browser then services vector `0x30` at `0x8001b030`.
- After that service, the later `0x80014f2d -> 0x80014f31 -> 0x80014f32 ->
  0x80030e84` first-read path has no pending interrupt, so the first watched
  read still consumes `0x00000000`.
- The next timer IRQ is observed only at `0x80030e84`, after the first watched
  read point, and the watched word then advances to one tick.

The existing code already contains a more precise pre-first-read scheduler gate:

- `xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready()` requires the
  opt-in scheduler mode, entry-ready, loaded image, a live virtual timer, and a
  serviceable CPU site (`xemu-xbe.c:2109`).
- It can treat the browser first-read predecessor after `STI` as a serviceable
  pump site even while `HF_INHIBIT_IRQ_MASK` is set, so the timer can become
  pending for the next CPU interrupt check before the watched read.

But that owner is currently unreachable at the exact place it is supposed to
act:

- `cpu_exec_loop()` calls `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()`
  immediately before `cpu_handle_interrupt()` (`accel/tcg/cpu-exec.c:1211`).
- `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` is hard-quarantined
  and always returns false (`xemu-xbe.c:2771`).
- `xemu_xbe_boot_trace_tcg_timer_pump_after_tb()` explicitly suppresses the
  after-TB pump when the pre-first-read scheduler site is ready
  (`xemu-xbe.c:2780`). This leaves the precise site with neither the intended
  before-interrupt pump nor the fallback after-TB pump.
- x86 will only deliver `CPU_INTERRUPT_HARD` when IF is set and
  `HF_INHIBIT_IRQ_MASK` is clear (`target/i386/cpu.c:9874`), so a pending timer
  created after the watched read is too late.

## Decision

The blocker is not a missing expired timer, bad watched address, or raw pump
count. It is a skipped CPU-owned service window:

```text
browser_pre_stream_vector_blocker=service-window-skipped-ready-edge-plus-quarantined-preinterrupt-owner
```

The ready-edge path proves timer delivery can happen but places it at the wrong
CPU service window. The narrow patch target is the existing pre-first-read
scheduler owner, not more PFIFO/PCRTC/vblank/runtime probing.

## Next Step

Run the required bounded sub-agent loop check before any patch. Ask whether the
next patch should re-enable `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()`
only when `xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready(false)`
is true, preserving the existing entry-ready/loaded/serviceable/expired-timer
guards and leaving the old broad before-interrupt path quarantined.

## Progress-Method Critique Included

No. This entry records the static inspection. The required follow-up loop check
must include the critique.
