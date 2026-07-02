# DMA PUT Boundary Static

## Purpose

- One new fact this run was supposed to produce: `browser_dma_put_stops_at_0x03881318_source`.

## Command(s)

```sh
rg -n "BOOT_MARK b6 pfifo=" xemu-xbe.c hw/xbox/nv2a

sed -n '2470,2500p' \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

sed -n '4188,4205p' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 40 "dma_put=0x03881318|dma_put=0x0388f814|dma_put=0x0388f888" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 40 "dma_put=0x03881318|dma_put=0x0388f814|dma_put=0x0388f888" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "^BOOT_MARK b6 pfifo=scheduler " \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 20

rg -n "^BOOT_MARK b6 pfifo=scheduler " \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | tail -n 20

rg -n "^BOOT_MARK b6 pfifo=progress " \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 20

rg -n "^BOOT_MARK b6 pfifo=progress " \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | tail -n 20
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Source inspected for marker inventory: `xemu-xbe.c`, `hw/xbox/nv2a/pfifo.c`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `browser_dma_put_stops_at_0x03881318_source`

## Findings

- Result: `browser_dma_put_stops_at_0x03881318_source=consumer-empty-no-existing-put-publication-proof`.
- Existing PFIFO marker names found in source:
  - `pfifo=scheduler`
  - `pfifo=window`
  - `pfifo=progress`
  - `pfifo=stream-idle-boundary`
  - `pfifo=stream-idle-transition`
  - `pfifo=pre-commit-timer-pump`
- The stable native and browser logs do not contain visible `pfifo=scheduler` lines for this static query.
- Browser consumes all commands it sees and reaches pusher-empty:
  - line 2493: `pfifo=window ... op=pusher-empty ... available=0 ... dma_get=0x03881318 dma_put=0x03881318 ... dma_state_method=0x1d94`
  - line 2495: `pfifo=stream-idle-boundary ... wait_op=pusher-empty dma_get=0x03881318 dma_put=0x03881318`
  - line 2496: `dashboard=kernel-loop-probe ... stream_idle=yes ... nv2a_dma_get=0x03881318 nv2a_dma_put=0x03881318`
- Native reaches the same GET boundary but has a much larger PUT and continues:
  - line 4192: `pfifo=window ... op=pusher-enter ... available=0 dma_get=0x03881318 dma_put=0x0388f814`
  - line 4193: `pfifo=window ... op=pusher-new-method-inc ... method=0x1710 available=14655 dma_get=0x03881318 dma_put=0x0388f814`
  - line 4197: `pfifo=window ... op=puller-method-done ... method=0x1710 dma_get=0x0388131c dma_put=0x0388f888`
- Browser and native both show early PFIFO progress with `dma_put=0x03881318`, so the early command stream is shared.
- The existing stable markers prove browser PFIFO consumption is not stuck: it drains to `available=0`.
- The existing stable markers do not prove the exact guest/MMIO writer or publication path that advances native `dma_put` from `0x03881318` to `0x0388f814` / `0x0388f888`.
- Classification: from current artifacts, browser has no observed later DMA PUT publication and no observed PFIFO consumption failure. The missing piece is upstream PUT publication or guest command submission after `0x03881318`, not method decode and not PFIFO pulling of available commands.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next step should inspect the code path that publishes NV2A/PFIFO DMA PUT and whether browser-specific scheduling can stop before the guest submits the native continuation. Do not assume PGRAPH method handling is wrong.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/261-dma-put-continuation-loop-check.md` requested bounded existing-log DMA PUT/GET continuation inspection.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the exact DMA_PUT/GET boundary remains connected to the late `0x1710` regime and strict `dashboard=xbe-executed`.
- If yes, process adjustment for next 2-3 turns: inspect only the DMA PUT publication path and browser stop condition; avoid old PFIFO classifier reruns and runtime probes unless static code cannot distinguish them.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether to inspect `pfifo_dma_put_publication_path_browser_stop_condition` in code or to stop for critique because the current artifacts lack a PUT publication marker.
