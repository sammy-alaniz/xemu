# 232. Post-Scheduler Pre-Stream Service Static

## Purpose

Perform the static source/log inspection approved by
`history/231-post-scheduler-next-direction-loop-check.md`.

The one field this inspection could explain was
`pre_service_tick_accumulation_owner_after_scheduler_quarantine`.

## Commands

```sh
scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n 'memory-watch|tick-block=complete|edge-decision|pit=irq-timer|pic=irq-ack|cpu=hard-irq-service|cpu=iret|main-loop=timers|tcg=timer-pump|headless=timer-pump-step' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n 'TICK_BLOCK_WATCH|TICK_BLOCK_PC|0x0003a890|0x80030e84|pit|PIT|irq-timer|timer|i8254|i8259|pic|PIC' \
  xemu-xbe.c hw/intc hw/timer hw/xbox include target/i386

sed -n '3700,3770p' build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
sed -n '2478,2538p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n -m 30 'tick-block=complete' build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
rg -n -m 30 'tick-block=complete' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n -m 20 'memory-watch context=native|memory-watch context=browser|access=write|access=read' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n 'start_pc=0x80014f5f|next_pc=0x80030e84|start_pc=0x80014f32|start_pc=0x80014f31|start_pc=0x80030e4c|start_pc=0x80030e84' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n 'start_pc=0x80014f5f|next_pc=0x80030e84|start_pc=0x80014f32|start_pc=0x80014f31|start_pc=0x80030e4c|start_pc=0x80030e84' \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n '0x80014f5f|0x80014f32|0x80014f31|FIRST_READ_PREDECESSOR|predecessor|edge=0x80014f|first_watch_read_edge|browser_first_watch_read_edge|native_first_watch_read_edge' \
  history scripts goal.md xemu-xbe.c

scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

Some broad `rg` output was intentionally treated as orienting only because the
logs contain very long lines and the output was truncated. The decisive output
for this entry is from the focused comparators.

## Inputs and Artifacts

- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Focused comparators:
  `scripts/xbox-pre-service-tick-gap-compare.py`,
  `scripts/xbox-post-service-watch-edge-compare.py`, and
  `scripts/xbox-pre-stream-tick-source-compare.py`

## Loop-Guard Fields

- `pre_service_tick_accumulation_owner_after_scheduler_quarantine`
- `browser_first_watch_read_ticks`
- `browser_pre_stream_service30`

## Findings

The stable pre-service tick gap remains unchanged:

- native first watched read: `0x80014f5f->0x80030e84`,
  `0x0014c080` / 136 ticks;
- browser first watched read: `0x80014f32->0x80030e84`,
  `0x00000000` / 0 ticks;
- browser first service happens before the read, but the watched-word write
  still happens after the read.

The stable post-service watch edge still passes:

- native block delta: 1 tick;
- browser block delta: 1 tick;
- divergence remains `pre-block-watch-value-mismatch`.

The focused pre-stream comparator is the sharpest post-quarantine result:

```text
PRE_STREAM_TICK_SOURCE_COMPARE result=pass
divergence=browser-lacks-pre-stream-vector-service
native_pre_stream_pit_rising=64
native_pre_stream_timer_progress=69
native_pre_stream_hard_irq_set=64
native_pre_stream_pic_ack30=53
native_pre_stream_service30=27
native_pre_stream_iret_after=64
browser_pre_stream_pit_rising=0
browser_pre_stream_timer_progress=0
browser_pre_stream_hard_irq_set=0
browser_pre_stream_pic_ack30=0
browser_pre_stream_service30=0
browser_pre_stream_iret_after=0
browser_post_stream_service30=3
```

That means the native tick accumulation owner is not a new scheduler hook. It
is existing pre-stream PIT/PIC/vector service and guest execution before the
eventual post-stream first watched read. The browser stable baseline lacks that
entire pre-stream vector-service class and only services vector `0x30` after
stream-idle, too late for the first watched read.

This also explains why scheduler/pump attempts were fragile: they tried to
manufacture the missing pre-stream service ordering after the browser path had
already entered a different post-stream sequence.

## Decision

`pre_service_tick_accumulation_owner_after_scheduler_quarantine=pre_stream_vector_service_gap`

The next target should not be another scheduler or pump variant. The remaining
causal question is why browser runtime has zero pre-stream PIT/PIC/vector
service while native has many, and whether that can be explained from existing
source/log evidence without rerunning old B3/B4/B5, PFIFO, DMA_PUT, or
scheduler experiments.

## Progress-Method Critique

This re-centers the work on a stable, non-quarantined divergence tied directly
to strict dashboard execution. It moves away from tuning failed scheduler
branches and toward identifying why the browser lacks the native service class
that actually accumulates the watched word.

## Next Step

Run the required loop check. Ask whether the next action should be a bounded
static source/log inspection of the missing pre-stream vector-service class, or
whether this is already covered by historical negative pump/vblank work and
should stop.
