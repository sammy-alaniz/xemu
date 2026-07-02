# Pre-First-Read Scheduler No Watch Update Static

## Purpose

- One new fact this run was supposed to produce: why
  `phase=timer-pump timer_deliveries=1` did not update physical `0x0003a890`
  before the first watched read in runtime V2.

## Command(s)

```sh
rg -n "3a890|memory_watch|tick-block|tick_block|pre-first-read|pre_first_read|timer_pump|timer-pump|xemu_xbe_tcg_timer|xemu_xbe_boot_trace_tcg" xemu-xbe.c include hw target accel scripts
rg -n "start_pc=0x80030e84|next_mem_addr=0x8003a890|pre_watch_value|post_watch_value|scheduler=pre-first-read|cpu=hard-irq-service|pic=irq-ack|cpu=iret|iret" build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2/browser-runtime.log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
sed -n '1,240p' history/334-first-watch-read-gap-owner-helper.md
sed -n '1,260p' history/336-browser-pre-stream-vector-blocker-static.md
sed -n '60,110p' xemu-xbe.c
sed -n '480,535p' xemu-xbe.c
sed -n '1610,2295p' xemu-xbe.c
sed -n '2680,2855p' xemu-xbe.c
sed -n '4210,4435p' xemu-xbe.c
sed -n '4760,4945p' xemu-xbe.c
sed -n '1200,1230p' accel/tcg/cpu-exec.c
sed -n '9860,9890p' target/i386/cpu.c
rg -n "xemu_boot_trace_tcg_timer_pump|enter_tcg_timer_pump|leave_tcg_timer_pump|note_timer_pump" -S .
rg -n "xemu_xbe_boot_trace_tick_block_pre_tb|xemu_xbe_boot_trace_edge_decision_pre_tb|xemu_xbe_boot_trace_pre_first_read_scheduler_after_tb|xemu_xbe_boot_trace_observe_exec" accel target include xemu-xbe.c xemu-xbe.h
sed -n '960,1055p' accel/tcg/cpu-exec.c
sed -n '7240,7355p' xemu-xbe.c
nl -ba xemu-xbe.c | sed -n '74,90p'
nl -ba accel/tcg/cpu-exec.c | sed -n '979,1038p'
nl -ba accel/tcg/cpu-exec.c | sed -n '1207,1282p'
nl -ba target/i386/cpu.c | sed -n '9868,9883p'
nl -ba xemu-xbe.c | sed -n '1636,1668p'
nl -ba xemu-xbe.c | sed -n '2109,2228p'
nl -ba xemu-xbe.c | sed -n '4223,4305p'
nl -ba xemu-xbe.c | sed -n '4305,4430p'
nl -ba xemu-xbe.c | sed -n '4762,4920p'
nl -ba build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2/browser-runtime.log | sed -n '2756,2788p'
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/browser-guarded-preinterrupt-scheduler-runtime-v2/browser-runtime.log`
- Fixture assumptions: not relevant; this was static code/log analysis only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_scheduler_timer_delivery_no_watch_update_reason`.

## Findings

- Result:
  `pre_first_read_scheduler_timer_delivery_no_watch_update_reason=timer-delivery-is-irq-state-not-watch-word-producer`.
- The watched word is tied to the guest tick block, not to the timer callback:
  `XEMU_XBE_TICK_BLOCK_PC=0x80030e84`,
  `XEMU_XBE_TICK_BLOCK_NEXT_PC=0x80030f31`,
  `XEMU_XBE_TICK_BLOCK_WATCH_PHYS=0x0003a890`, and
  `XEMU_XBE_TICK_BLOCK_TICK_UNIT=0x2710` are defined together in
  `xemu-xbe.c`.
- `xemu_boot_trace_tcg_timer_pump()` runs QEMU virtual timers under BQL and
  records progress; in PIT-only mode it runs one matching timer callback. It
  does not write `0x0003a890`.
- The producer evidence is the tick-block probe:
  `xemu_xbe_boot_trace_tick_block_pre_tb()` samples the watched word before
  guest TB `0x80030e84`, and
  `xemu_xbe_boot_trace_tick_block_post_tb()` samples it again only after the TB
  exits to `0x80030f31`.
- Runtime V2 confirms this ordering:
  - scheduler starts at `0x80014f32` with `watch_ticks=0`;
  - PIT timer pump delivers one interrupt and sets `CPU_INTERRUPT_HARD`;
  - the edge into `0x80030e84` still samples
    `next_mem_addr=0x8003a890 ... next_mem_value=0x00000000`;
  - only after that does vector `0x30` service run at `0x80030e84`;
  - then the tick block executes and advances `0x0003a890` from 0 to 1 tick.
- The x86 interrupt gate explains why pumping at the STI-inhibited predecessor
  is insufficient: hard IRQ delivery requires IF set and
  `HF_INHIBIT_IRQ_MASK` clear. Runtime V2 pumps while `irq_inhibited=yes`;
  delivery happens at `0x80030e84`, after the sampled first-read edge is already
  recorded.
- The original hypothesis in the code comment was too optimistic: making an IRQ
  pending at the first-read predecessor does not itself make the watched word
  native-like. Native has already executed substantial pre-stream
  timer/vector/tick-block production before the first watched read; V2 only
  creates one interrupt and then lets the producer block run after the zero
  sample.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not
  applicable; no emulator run occurred.

## Decision

- Status: current
- Why: this explains runtime V2's no-update result without another run. The
  guarded scheduler is not a direct producer of the tick word; it can only
  schedule guest code that might later produce it.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history 345 required a static causal explanation
  before any further runtime.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: history 345 warned that repeated
  pump-placement proof was becoming circular and required identifying the
  actual producer path.
- If yes, process adjustment for next 2-3 turns: do not rerun runtime. Decide
  whether to rewrite the guarded branch into a deterministic producer strategy
  or remove it, based on a loop check.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  Ask whether the next change should revise the branch toward deterministic
  guest tick production before the first read, or stop/remove the branch.
