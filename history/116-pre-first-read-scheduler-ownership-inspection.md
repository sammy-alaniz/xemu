# Pre First Read Scheduler Ownership Inspection

## Purpose

- One new fact this inspection was supposed to produce:
  `pre_first_read_timer_delivery_owner`, the best ownership point for
  deterministic timer/IRQ delivery before the browser first watched read at
  `0x80014f32->0x80030e84`.

## Command(s)

```sh
rg -n "browser.*timer|HEADLESS_TIMER|headless.*timer|main-loop=timers|timer_pump|deterministic|BROWSER_BOOT_DETERMINISTIC|qemu_clock_run_timers|qemu_clock_deadline_ns_all|timer_progress|progress_limit|pfifo-ready-edge|browser-ready-edge|browser-headless-host-pump" \
  ui/xemu-headless.c util/main-loop.c system/vl.c xemu-xbe.c \
  browser/xbox-boot/worker.js browser/xbox-boot/main.js \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs accel/tcg/cpu-exec.c

nl -ba ui/xemu-headless.c | sed -n '636,830p'
nl -ba ui/xemu-headless.c | sed -n '940,1005p'
nl -ba xemu-xbe.c | sed -n '940,1160p'
nl -ba xemu-xbe.c | sed -n '1780,1910p'
nl -ba accel/tcg/cpu-exec.c | sed -n '970,1036p'
nl -ba util/main-loop.c | sed -n '649,730p'
nl -ba util/qemu-timer.c | sed -n '600,720p'
nl -ba xemu-xbe.c | sed -n '6070,6168p'

sed -n '1,220p' history/64-deterministic-browser-m1-v1.md
sed -n '1,220p' history/66-deterministic-warmup1-browser-runtime.md
sed -n '1,220p' history/67-deterministic-warmup-loop-check.md
sed -n '1,220p' history/70-post-service-edge-decision-static-compare.md
sed -n '1,220p' history/98-ready-edge-timer-steps-runtime.md
sed -n '1,220p' history/99-ready-edge-timer-steps-loop-check.md
sed -n '1,220p' history/100-watch-word-producer-static-inspection.md
sed -n '1,220p' history/102-tick-block-completion-marker-runtime.md

rg -n "main-loop=timers context=browser-runtime source=main-loop-wait" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log \
  build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

rg -n "main-loop=timers context=browser-runtime source=(browser-ready-edge-qemu-pump|browser-headless-host-pump-bounded|browser-deterministic-pump)" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log \
  build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log | sed -n '1,80p'

scripts/xbox-post-service-edge-decision-compare.py \
  --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  --log det2=build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log \
  --log warmup1=build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log \
  --log highhalf=build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
```

## Inputs And Artifacts

- Active browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Deterministic browser artifacts:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`
  and
  `build-real-b3-matrix/browser-main-menu-deterministic-warmup1-v1-combined.log`
- High-half negative artifact:
  `build-real-b3-matrix/browser-tick-block-irq-defer-highhalf-readyedge-host4-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Source files inspected:
  `ui/xemu-headless.c`, `util/main-loop.c`, `util/qemu-timer.c`,
  `accel/tcg/cpu-exec.c`, and `xemu-xbe.c`
- Fixture assumptions: no-emulation source/log inspection only.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `pre_first_read_timer_delivery_owner`, with `browser_first_watch_read_ticks`
  and post-service edge preservation as the next runtime guards.

## Findings

- Result: the browser-specific host pump is not a stable ownership point for
  deterministic timer/IRQ delivery. It runs from the headless browser polling
  loop, uses `bql_try_lock()`, and can land at different guest PCs depending on
  when that host loop wins the lock.
- The host-pump implementation in `ui/xemu-headless.c` can run one or more
  bounded virtual timers with
  `qemu_clock_run_timers_with_attrs_limit(QEMU_CLOCK_VIRTUAL, 0, 0, 1)` and
  then logs `main-loop=timers` with sources such as
  `browser-headless-host-pump-bounded` or `browser-deterministic-pump`.
- Existing deterministic mode is still host-loop owned. It can force warmup
  progress when entry-ready and expired virtual timers are present, but it is
  still gated by polling cadence and BQL availability.
- Regular QEMU `main_loop_wait()` owns `qemu_clock_run_all_timers()` on the
  QEMU main-loop path and logs `source=main-loop-wait`, but none of the
  checked browser artifacts contain a `main-loop-wait` timer marker. In these
  runs, browser-visible timer progress comes only from diagnostic browser
  sources.
- The current active ready-edge host4 baseline preserves the useful
  post-service edge and reaches one tick:
  `top_edge=0x80030e84->0x80030f31`,
  `first_watch_read_ticks=1`, and
  `first_block_start_ticks=2`.
- Deterministic M1 v1 proves host-loop deterministic delivery can move the
  primary tick field from 0 to 2, but it breaks the useful edge:
  `top_edge=0x80030e4c->0x80014f32`,
  `first_watch_read_ticks=2`,
  `first_block_edge=0x80030e84->0x80030f45`, and
  `classification=block-start-branch-mismatch`.
- Warmup1 proves raw warmup count is not the control knob:
  it loses the focused read and falls back to
  `top_edge=0x8001b02f->0x8001b030`.
- Ready-edge steps=2 is also negative evidence:
  extra callbacks happened before the first watched read, but
  `browser_first_watch_read_ticks` remained 0 and the post-service edge
  regressed.
- The watched word is produced by guest execution of the tick block, not by the
  host timer callback directly writing low RAM. Timer callbacks schedule/assert
  PIT/PIC state; CPU execution must then service the IRQ and execute guest code
  through the `0x80030e84` block.
- `pre_first_read_timer_delivery_owner` should therefore not be the
  browser-headless polling loop. The next design should own deterministic
  delivery on an emulation-thread boundary that pairs PIT/PIC timer delivery
  with bounded guest execution, and must preserve the baseline
  `0x80030e84->0x80030f31` edge.

## Decision

- Status: current design inspection.
- Why: this inspection explains why host-pump counts and exact-PC deferral are
  unstable. The useful next code slice should be designed around ordered
  PIT/PIC delivery plus guest tick-block completion, not another host-poll
  timer placement.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/115` approved returning to scheduler
  ownership inspection and required the next runtime-worthy field to be
  `browser_first_watch_read_ticks` or a direct scheduler prerequisite.

## Progress-Method Critique

- The method is back on the path to strict dashboard execution because it
  targets the tick/CPU ordering gap that blocks browser-runtime
  `dashboard=xbe-executed`.
- This was a necessary consolidation pass after the dead-end exact-PC defer
  slice, but more static reading without a bounded design would become
  diagnostic-heavy again.
- The history/loop-check process helped stop raw host-pump count tuning and
  exact-PC defer variants.
- The right next mode is a bounded design/code step, not another runtime: define
  a deterministic emulation-thread scheduler checkpoint that can change
  `browser_first_watch_read_ticks` while preserving the post-service edge.
- Process adjustment for the next 2-3 turns: do not use browser host-pump count
  or exact-PC IRQ defer as the next experimental variable.

## Next Step

- Narrow follow-up: run the required loop check. If it approves, inspect or
  implement a small emulation-thread deterministic scheduler checkpoint whose
  success criteria are `browser_first_watch_read_ticks > 1` and preserved
  `0x80030e84->0x80030f31` edge, with strict B6 unchanged.
