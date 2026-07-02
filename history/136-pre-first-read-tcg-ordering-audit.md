# 136. Pre-first-read TCG ordering audit

## Purpose

Explain why the new `pit-post-pfifo-pre-first-read` TCG pump marker appears but does not improve the first browser read of physical `0x0003a890`.

## Loop-Guard Field

- `tcg_pump_after_first_read_reason`

## Exact Commands

```sh
sed -n '2638,2672p' \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log

sed -n '3744,3762p' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n "xemu_xbe_boot_trace_observe_exec|tcg_timer_pump|tick-block|edge-decision|xemu_xbe_boot_trace_observe_exec_transition|observe_exec_transition|tcg-tb-pre|tcg-tb-post|memory_watch" \
  xemu-xbe.c accel target hw include

rg -n "xemu_xbe_boot_trace_observe_exec|xemu_xbe_boot_trace_observe_exec_transition|xemu_xbe_boot_trace_tcg_timer_pump|cpu_tb_exec|tb_exit|tcg-tb" .

sed -n '960,1150p' accel/tcg/cpu-exec.c
sed -n '1400,1988p' xemu-xbe.c
sed -n '3360,4245p' xemu-xbe.c
sed -n '8848,9148p' xemu-xbe.c

rg -n "xemu_xbe_nv2a_wait_snapshot_is_pfifo_empty|xemu_xbe_nv2a_wait_is_stream_idle|latest_pfifo_stream_idle|latest_nv2a_wait_state|xemu_xbe_boot_trace_latest_pfifo_stream_idle_state|xemu_xbe_boot_trace_latest_nv2a_wait_state" \
  xemu-xbe.c hw/xbox/nv2a

rg -n "0x80014f5f|0x80014f32|0x80018e07|first_watch_read|browser_first_service|native_first_watch" \
  history/*.md scripts/xbox-pre-service-tick-gap-compare.py goal.md AGENTS.md

rg -n "headless=timer-pump-step|main-loop=timers|pit=irq-timer|pic=irq-line|cpu=hard-irq|cpu=hard-irq-service|cpu=iret|tcg=timer-pump|tick-block=complete|memory-watch" \
  build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log
```

## Inputs and Artifacts

- Browser combined log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log`
- Native reference:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Source:
  `accel/tcg/cpu-exec.c`
  `xemu-xbe.c`
- Comparator:
  `scripts/xbox-pre-service-tick-gap-compare.py`

## Findings

- The current `pit-post-pfifo-pre-first-read` mode is not a before-TB mode.
  `xemu_xbe_boot_trace_tcg_timer_pump_before_tb()` only returns true for
  `pit-before-pfifo-transition-activity-pre-tb-defer`.
- In `cpu_loop_exec_tb()`, the normal after-TB order is:
  `cpu_tb_exec()`,
  `edge_decision_post_tb()`,
  `tick_block_post_tb()`,
  `observe_exec_transition()`,
  then `xemu_boot_trace_tcg_timer_pump()`.
- Therefore the `kernel-loop-probe` lines that report the first observed
  shared-word read are emitted before the current TCG pump runs.
- For this artifact, the browser first observed shared-word read is line 2650:
  `0x80014f32->0x80030e84`, value `0x00000000`, with pending interrupt.
- After IRQ service and IRET, browser reaches `0x80030e84` again at line 2660,
  still reading value `0x00000000`.
- The TCG pump fires at line 2667 with `timer_progress=yes`, but the watched
  write callback at line 2669 still sees pre-access value `0x00000000`.
- The tick block at line 2670 then writes one tick:
  `pre_watch_ticks=0`, `post_watch_ticks=1`.
- This means the TCG pump does not itself produce the native-like watched-word
  accumulation before the `0x80030e84` block reads the word.
- Native already has the watched word populated before the analogous read:
  first native post-transition read is `0x80014f5f->0x80030e84` with
  `0x0014c080` / 136 ticks.
- Native reaches that read with no pending interrupt at the PFIFO idle boundary.
  Browser reaches the first read through `0x80014f32->0x80030e84` with pending
  interrupt, then services vector `0x30` before returning to the same block.
- The edge-decision skip after the TCG pump is a secondary symptom:
  the latest wait snapshot has changed to `pcrtc/vblank-suppress`, while the
  previous PFIFO idle snapshot is still present. Using the latest wait snapshot
  alone makes `stream-idle-gate-false` after PFIFO idle has already been proven.

## Decision

`tcg_pump_after_first_read_reason=after-tb-observation-order-and-nonproducer`

The current TCG pump path is not sufficient for the primary metric. It runs
after transition observations and, even when it runs before the actual
`0x80030e84` block execution, it does not update physical `0x0003a890` before
that block's read. The remaining blocker is earlier timer/tick accumulation and
CPU/IRQ ordering before the browser reaches `0x80014f32->0x80030e84`, not the
closed PC predicate alone.

## Next Step

Run the required bounded loop check before any code change. Ask whether to
revise away from the current TCG pump and toward a deterministic pre-read
scheduler/timer owner that can move `browser_first_watch_read_ticks`, while
preserving B4/B5, read/load/entry-ready, PFIFO stream-idle, IRQ/IRET, and not
weakening strict `dashboard=xbe-executed`.
