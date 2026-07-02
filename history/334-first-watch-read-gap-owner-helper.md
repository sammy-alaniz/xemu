# 334 - First Watch Read Gap Owner Helper

## Purpose

Add and run a focused static helper for the loop-guard field
`first_watch_read_tick_gap_owner`.

This follows the loop-check recommendation from
`history/333-cpu-hard-request-cleared-loop-check.md`: stop treating PCRTC
final-window forcing as the main path unless a native comparison proves it is
causal, and instead classify who owns the first watched-read tick gap.

## Commands

```sh
python3 -m py_compile scripts/xbox-first-watch-read-gap-owner.py
```

```sh
python3 scripts/xbox-first-watch-read-gap-owner.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs / Artifacts

- Helper: `scripts/xbox-first-watch-read-gap-owner.py`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Field

- `first_watch_read_tick_gap_owner`

## Findings

The helper compiled and reported:

```text
FIRST_WATCH_READ_GAP_OWNER result=pass
first_watch_read_tick_gap_owner=browser-lacks-native-pre-stream-vector-timer-production
first_watch_read_tick_delta=136
```

Key native side fields:

- `native_xbe_executed=yes`
- `native_first_watch_read_edge=0x80014f5f->0x80030e84`
- `native_first_watch_read_value=0x0014c080`
- `native_first_watch_read_ticks=136`
- `native_pre_stream_timer_progress=69`
- `native_pre_stream_pit_rising=64`
- `native_pre_stream_hard_irq_set=64`
- `native_pre_stream_hard_irq_reset=64`
- `native_pre_stream_pic_ack30=53`
- `native_pre_stream_service30=27`
- `native_pre_stream_iret_after=64`
- `native_last_pre_transition_watch_read_ticks=85`

Key browser side fields:

- `browser_xbe_executed=no`
- `browser_first_watch_read_edge=0x80014f32->0x80030e84`
- `browser_first_watch_read_value=0x00000000`
- `browser_first_watch_read_ticks=0`
- `browser_pre_stream_timer_progress=0`
- `browser_pre_stream_pit_rising=0`
- `browser_pre_stream_hard_irq_set=0`
- `browser_pre_stream_hard_irq_reset=0`
- `browser_pre_stream_pic_ack30=0`
- `browser_pre_stream_service30=0`
- `browser_pre_stream_iret_after=0`
- `browser_first_post_transition_service_intno=0x30`
- `browser_first_post_transition_timer_source=browser-ready-edge-qemu-pump`
- `browser_first_post_transition_timer_watch_ticks=0`
- `browser_last_pre_read_timer_source=browser-headless-host-pump-bounded`
- `browser_last_pre_read_timer_watch_ticks=0`

This preserves the existing strict B6 result: the browser still has no
`dashboard=xbe-executed` marker. The new classification explains the 136-tick
gap as a missing pre-stream vector/timer-production phase in the browser
baseline, not as a watch-address mismatch or memory-watch callback artifact.

## Decision

Revise away from the PCRTC final-window forcing branch as the primary path.
That branch proved BQL and IRQ assertion were not enough, but this helper shows
the broader missing piece: native accumulates PIT/vector/timer work before the
first watched read, while the current browser baseline performs none of that
pre-stream work and reaches the watched read at zero ticks.

## Next Step

Run the required bounded sub-agent loop check before any next experiment,
probe, or code change. The loop-check prompt must include a
Progress-Method Critique and ask whether the next action should inspect why the
browser has no pre-stream vector/timer-production phase, or whether a different
causal slice is now better.

## Progress-Method Critique Included

No. This entry records the helper implementation and output; the next required
loop-check entry must include the critique.
