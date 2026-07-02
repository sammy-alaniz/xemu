# PGRAPH Command Stream Helper

## Purpose

- One new fact this run was supposed to produce: `post_early_notify_clear_native_continuation_absent_in_browser`.

## Command(s)

```sh
sed -n '1,260p' scripts/xbox-pgraph-command-stream-compare.py

sed -n '1,140p' scripts/xbox-pgraph-command-stream-compare-selftest.sh

scripts/xbox-pgraph-command-stream-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Helper: `scripts/xbox-pgraph-command-stream-compare.py`
- Output directory/log: existing logs only.
- Fixture assumptions: static helper only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `post_early_notify_clear_native_continuation_absent_in_browser`

## Findings

- Result: `post_early_notify_clear_native_continuation_absent_in_browser=browser-stops-after-early-notify-clear-and-stream-idle-while-native-continues-command-stream`.
- Helper result:
  - `PGRAPH_COMMAND_STREAM_COMPARE result=pass`
  - `divergence=native-extra-notify-clear`
  - `command_stream_aligned=no`
  - `native_xbe_executed=yes`
  - `browser_xbe_executed=no`
- Native continuation:
  - `native_notify_error=128`
  - `native_notify_clear=128`
  - `native_last_trapped_data=0x0000031c`
  - `native_last_dma_get=0x0388dd30`
  - `native_last_dma_put=0x038aed98`
  - `native_stream_idle=no`
  - `native_pfifo_window=512`
  - `native_pfifo_window_op=puller-method`
  - `native_pfifo_window_dma_get=0x0388141c`
  - `native_pfifo_window_dma_put=0x0388f888`
  - `native_pfifo_window_method=0x1710`
  - `native_pgraph_method_window=256`
  - `native_pgraph_window_phase=unhandled`
  - `native_pgraph_window_method=0x1710`
  - `native_loop_start_pc=0x8001e374`
  - `native_loop_next_pc=0x8001e374`
  - `native_loop_kind=self`
  - `native_loop_wait_source=pgraph-notify-clear`
  - `native_loop_wait_op=notify-error-clear`
  - `native_loop_wait_seq=128`
- Browser state:
  - `browser_notify_error=8`
  - `browser_notify_clear=8`
  - `browser_last_trapped_data=0x00000304`
  - `browser_last_dma_get=0x03880e30`
  - `browser_last_dma_put=0x03881318`
  - `browser_stream_idle=yes`
  - `browser_pfifo_window=379`
  - `browser_pfifo_window_op=pusher-empty`
  - `browser_pfifo_window_dma_get=0x03881318`
  - `browser_pfifo_window_dma_put=0x03881318`
  - `browser_pfifo_window_method=0x0000`
  - `browser_pgraph_method_window=200`
  - `browser_pgraph_window_phase=exit`
  - `browser_pgraph_window_method=0x1d90`
  - `browser_loop_start_pc=0x8001b02f`
  - `browser_loop_next_pc=0x8001b030`
  - `browser_loop_kind=fallthrough`
  - `browser_loop_wait_source=pfifo-window`
  - `browser_loop_wait_op=pusher-empty`
  - `browser_loop_wait_seq=379`
- Classification: browser reaches and clears the early PGRAPH notify-error sequence, then arrives at a PFIFO pusher-empty stream-idle state. Native does not stop there; it continues into many more notify-error/notify-clear and method-window events, ending in the `0x1710` / `trapped_data=0x0000031c` late PGRAPH regime before direct low XBE execution.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next field should explain why browser ends the command stream at `0x03881318`/method `0x1d90` while native continues to the later `0x1710` PGRAPH method-window/notify-clear sequence. This is closer to the missing strict marker than another timer or generic PFIFO run.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/257-post-early-notify-helper-loop-check.md` recommended this focused helper first.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the helper is acceptable because it stays tied to the missing late handoff before strict `dashboard=xbe-executed`.
- If yes, process adjustment for next 2-3 turns: compare only the post-`0x03881318` continuation path and method IDs, not broad graphics behavior.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether to inspect `native_method_0x1710_continuation_absent_in_browser` statically, using bounded method-window/PFIFO lines around browser's last `0x1d90` and native's first `0x1710`.
