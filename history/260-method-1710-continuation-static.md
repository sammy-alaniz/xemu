# Method 1710 Continuation Static

## Purpose

- One new fact this run was supposed to produce: `native_method_0x1710_continuation_absent_in_browser`.

## Command(s)

```sh
rg -n -m 20 "^BOOT_MARK b6 pgraph=method-window .*method=0x1710" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 20 "^BOOT_MARK b6 pgraph=method-window .*method=0x1710" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n -m 20 "^BOOT_MARK b6 pfifo=window .*method=0x1710" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 20 "^BOOT_MARK b6 pfifo=window .*method=0x1710" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "^BOOT_MARK b6 pgraph=method-window " \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 12

rg -n "^BOOT_MARK b6 pfifo=window " \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 12
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `native_method_0x1710_continuation_absent_in_browser`

## Findings

- Result: `native_method_0x1710_continuation_absent_in_browser=browser-reaches-stream-idle-before-dma-continuation`.
- Native first `0x1710` PFIFO window begins immediately after the point where browser stops:
  - line 4193: `pfifo=window ... op=pusher-new-method-inc ... method=0x1710 ... available=14655 ... dma_get=0x03881318 dma_put=0x0388f814`
  - line 4194: `pfifo=window ... op=puller-method ... method=0x1710 ... dma_get=0x0388131c dma_put=0x0388f814`
  - line 4197: `pfifo=window ... op=puller-method-done ... method=0x1710 ... dma_get=0x0388131c dma_put=0x0388f888`
- Native first `0x1710` PGRAPH method-window follows the same continuation:
  - line 4195: `pgraph=method-window ... phase=enter ... method=0x1710 ... available=1 ... dma_get=0x0388131c dma_put=0x0388f888`
  - line 4196: `pgraph=method-window ... phase=unhandled ... method=0x1710 ... processed=1 ... dma_get=0x0388131c dma_put=0x0388f888`
- Browser has no `pgraph=method-window ... method=0x1710` matches.
- Browser has no `pfifo=window ... method=0x1710` matches.
- Browser's last method-window sequence ends at `0x1d90`:
  - line 2478: `pgraph=method-window ... phase=enter ... method=0x1d90 ... dma_get=0x0388130c dma_put=0x03881318`
  - line 2479: `pgraph=method-window ... phase=exit ... method=0x1d90 ... processed=1 ... dma_get=0x0388130c dma_put=0x03881318`
  - line 2484: `pgraph=method-window ... phase=enter ... method=0x1d90 ... dma_get=0x03881314 dma_put=0x03881318`
  - line 2485: `pgraph=method-window ... phase=exit ... method=0x1d90 ... processed=1 ... dma_get=0x03881314 dma_put=0x03881318`
- Browser's PFIFO reaches pusher-empty at the exact boundary where native still has a large DMA continuation:
  - line 2493: `pfifo=window ... op=pusher-empty ... available=0 ... dma_get=0x03881318 dma_put=0x03881318 ... dma_state_method=0x1d94`
- Classification: browser is not failing to decode or handle method `0x1710`. The stable browser log never has the DMA continuation that contains `0x1710`; it reaches PFIFO stream-idle too early at `0x03881318`, while native has `dma_put` advanced to `0x0388f814` / `0x0388f888` and thousands of available words.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next boundary is upstream of PGRAPH method handling. It should explain why browser's PFIFO/DMA producer stops publishing at `dma_put=0x03881318` while native has a large post-`0x03881318` command continuation before strict dashboard execution.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/259-method-1710-continuation-loop-check.md` requested this bounded method comparison.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said this comparison remains connected to the native command-stream continuation before actual low XBE execution.
- If yes, process adjustment for next 2-3 turns: target PFIFO/DMA command production/PUT publication after `0x03881318`; do not edit method decode or weaken strict execution checks.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether to inspect `browser_dma_put_stops_at_0x03881318_source` statically from existing PFIFO producer/window/scheduler markers.
