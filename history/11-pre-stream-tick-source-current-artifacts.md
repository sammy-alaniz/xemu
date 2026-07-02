# Pre-Stream Tick Source Current Artifacts

## Purpose

- One new fact this run was supposed to produce: whether the native/browser `0x0003a890` first watched-read gap is explained by native having pre-stream PIT/vector `0x30` service while the browser baseline has none before PFIFO stream-idle.

## Command(s)

```sh
scripts/xbox-pre-stream-tick-source-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-b6-current-boundary.sh
```

## Inputs And Artifacts

- Native baseline: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser baseline: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native memory-watch support log used by boundary helper: `build-real-b3-matrix/native-memory-watch-write-0x3a890-v2/boot-smoke.log`
- Output: command stdout only; no new emulation run or fixture mutation.

## Expected Field(s)

- Loop-guard field explained: `pre_service_browser_first_watch_read_ticks`.

## Findings

- Result: current evidence.
- `PRE_STREAM_TICK_SOURCE_COMPARE result=pass divergence=browser-lacks-pre-stream-vector-service`.
- The first watched-read tick delta remains `136`: native reads `0x0003a890` at `136` ticks and browser reads it at `0` ticks.
- Native before first PFIFO stream-idle:
  - `native_pre_stream_pit_rising=64`
  - `native_pre_stream_timer_progress=69`
  - `native_pre_stream_hard_irq_set=64`
  - `native_pre_stream_pic_ack30=53`
  - `native_pre_stream_service30=27`
  - `native_pre_stream_iret_after=64`
- Browser before first PFIFO stream-idle:
  - `browser_pre_stream_pit_rising=0`
  - `browser_pre_stream_timer_progress=0`
  - `browser_pre_stream_hard_irq_set=0`
  - `browser_pre_stream_pic_ack30=0`
  - `browser_pre_stream_service30=0`
  - `browser_pre_stream_iret_after=0`
- Browser does service vector `0x30`, but only after stream-idle: `browser_post_stream_service30=3`, with first post-stream service at `eip=0x8001b030`.
- Native already saw a pre-stream watched read at line `1084`, edge `0x8003adcc->0x80030e84`, with `85` ticks; the first post-transition watched read is line `3755`, edge `0x80014f5f->0x80030e84`, with `136` ticks.
- The boundary helper now emits `B6_CURRENT_BOUNDARY_PRE_STREAM_TICK_SOURCE` with the same divergence and still reports strict B6 as incomplete: `b6=fail b6_reason=missing-xbe-executed-marker`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation run was performed. The boundary helper still summarizes B4/B5/read/load/entry-ready/section-map and current post-service evidence from the front-most logs, but browser `dashboard=xbe-executed` remains absent.

## Decision

- Status: current
- Why: this replaces the broad hand-scanned pre-stream hypothesis with countable evidence. The active blocker is now earlier than the ready-edge pump: browser lacks native-like pre-stream PIT/main-loop/vector `0x30` service before PFIFO stream-idle.
- Independent critique used: no

## Next Step

- Update `goal.md` to make this the current boundary. The next implementation slice should explain why browser has zero pre-stream PIT/timer/vector service before stream-idle, rather than rerunning ready-edge/all-timers/post-stream pump variants.
