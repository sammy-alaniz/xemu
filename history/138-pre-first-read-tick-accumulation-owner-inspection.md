# Pre-First-Read Tick Accumulation Owner Inspection

## Purpose

- One new fact this inspection was supposed to produce: identify which part of the emulator should own browser tick accumulation before the first watched `0x0003a890` read, instead of repeating known pump-placement probes.

## Command(s)

```sh
rg -n "DETERMINISTIC|deterministic|TIMER_STEPS|timer_steps|ready-edge|ready_edge|HEADLESS_TIMER_PUMP|headless_timer|qemu-pump|timer-pump-step|browser-ready-edge" .
sed -n '300,830p' ui/xemu-headless.c
sed -n '920,1160p' xemu-xbe.c
sed -n '608,660p' hw/xbox/nv2a/pfifo.c
sed -n '1368,1390p' hw/xbox/nv2a/pfifo.c
sed -n '720,930p' accel/tcg/cpu-exec.c
sed -n '960,1150p' accel/tcg/cpu-exec.c
sed -n '1178,1275p' accel/tcg/cpu-exec.c
sed -n '6140,6385p' xemu-xbe.c
sed -n '120,220p' xemu-xbe.h
sed -n '1,220p' history/64-deterministic-browser-m1-v1.md
sed -n '1,220p' history/70-post-service-edge-decision-static-compare.md
sed -n '1,220p' history/100-watch-word-producer-static-inspection.md
sed -n '1,220p' history/102-tick-block-completion-marker-runtime.md
sed -n '1,220p' history/116-pre-first-read-scheduler-ownership-inspection.md
sed -n '1,220p' history/118-emulation-thread-checkpoint-site-inspection.md
sed -n '1,220p' history/120-post-pfifo-pre-first-read-tcg-mode-build.md
rg -n "deterministic=timer-pump|main-loop=timers|tick-block=complete|memory-watch|kernel-loop-probe|cpu=hard-irq-service|cpu=iret|pic=irq-line" build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
scripts/xbox-pre-service-tick-gap-compare.py --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log --browser-log build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
scripts/xbox-post-service-edge-decision-compare.py --log baseline=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log --log det2=build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Supporting browser log: `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`
- Output directory/log: static source/history inspection only
- Fixture assumptions: current same-origin browser harness remains the valid runtime path; strict B6 still requires browser-runtime `dashboard=xbe-executed`.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain: `pre_first_read_tick_accumulation_owner`

## Findings

- Result: the stable owner should be an opt-in emulation-thread checkpoint, not another host polling or PFIFO placement variant.
- `ui/xemu-headless.c` owns browser host polling and deterministic host pump modes. Those paths can deliver timers, but they depend on host polling and `bql_try_lock()`, so they are not the clean owner for pre-first-read guest progress.
- `hw/xbox/nv2a/pfifo.c` owns the ready-edge QEMU-thread pump. This is deterministic placement, but current artifacts show it is too late or too limited to close the 136-to-0/1 tick gap by itself.
- `accel/tcg/cpu-exec.c` already owns the normal sequence that matters: run timers, let `cpu_handle_interrupt()` service pending IRQs normally, execute guest TBs, observe the first watched read, and preserve the useful post-service edge.
- Deterministic M1 proves ticks can move before the first read: browser first-read ticks reached 2. It also regressed the useful edge, with the post-service comparator reporting `classification=block-start-branch-mismatch` instead of the baseline `useful-post-service-edge`.
- The current `pit-post-pfifo-pre-first-read` TCG pump path explains timer delivery timing but not tick accumulation ownership: it can deliver a PIT timer at `0x80030e84`, but it does not by itself force normal guest execution through enough tick-block completions before the first watched read.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was started in this inspection. Existing deterministic M1 evidence still fails strict B6 and regresses the useful post-service edge; existing same-origin v2 evidence preserves B4/B5/read/load/entry-ready/section-map/stream-idle/IRET but keeps first-read ticks at 0.

## Decision

- Status: current
- Why: the next useful change should make pre-first-read tick accumulation an explicit, bounded, opt-in emulation-thread responsibility with stop reasons, instead of moving host-side pumps around the same boundary.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required bounded sub-agent loop check with a progress-method critique. Ask whether to implement one opt-in emulation-thread micro-scheduler/checkpoint whose measurable fields are `pre_first_read_tick_block_completions_browser`, `browser_first_watch_read_ticks`, and post-service edge preservation.
