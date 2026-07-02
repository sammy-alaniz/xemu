# DMA PUT Code Path Static

## Purpose

- One new fact this run was supposed to produce: `pfifo_dma_put_publication_path_browser_stop_condition`.

## Command(s)

```sh
rg -n "DMA_PUT|DMA_GET|dma_put|dma_get|CACHE1|pusher-empty|pusher_empty|pfifo=window|pfifo=progress|pfifo=scheduler|available|processed" \
  hw/xbox/nv2a/pfifo.c

sed -n '1,460p' hw/xbox/nv2a/pfifo.c

sed -n '460,900p' hw/xbox/nv2a/pfifo.c

rg -n "stream-idle|stream_idle|pusher-empty|pusher_empty|main_loop_timer_pump_ready|pfifo|XEMU_BROWSER_BOOT_HEADLESS|browser-headless|headless=timer|timer-pump" \
  xemu-xbe.c ui/xemu-headless.c browser/xbox-boot/main.js browser/xbox-boot/worker.js scripts/xbox-browser-runtime-smoke.sh

rg -n "pfifo_write|NV_PFIFO_CACHE1_DMA_PUT|regs\\[addr\\]|fifo_kick|pfifo_run_pusher|pusher_thread|update_irq|qemu_thread|timer|kick" \
  hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/*.c hw/xbox/nv2a/*.h

sed -n '900,1450p' hw/xbox/nv2a/pfifo.c

sed -n '1450,1720p' hw/xbox/nv2a/pfifo.c

sed -n '160,700p' ui/xemu-headless.c

sed -n '1030,1085p;1150,1180p;8750,8770p;8990,9065p' xemu-xbe.c

sed -n '180,375p' hw/xbox/nv2a/user.c

rg -n "NV_USER_DMA_PUT|NV_USER_DMA_GET|nv-user-dma-put|nv-user-dma-get|dma_put|pfifo_kick_with_source" \
  hw/xbox/nv2a/user.c hw/xbox/nv2a/user.h hw/xbox/nv2a/nv2a_regs.h

rg -n "nv-user-dma-put|kick_source=nv-user-dma-put|pfifo=scheduler|DMA_PUT|NV_USER_DMA_PUT" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

sed -n '1,180p' hw/xbox/nv2a/user.c

rg -n "XEMU_BOOT_TRACE_NV2A_USER|user_dma_put|nv2a=user-dma-put|user_boot_trace_dma_put" \
  AGENTS.md goal.md scripts browser hw/xbox/nv2a/user.c
```

## Inputs And Artifacts

- Source inspected: `hw/xbox/nv2a/pfifo.c`, `hw/xbox/nv2a/user.c`, `hw/xbox/nv2a/nv2a_regs.h`, `xemu-xbe.c`, `ui/xemu-headless.c`, browser fixture plumbing.
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `pfifo_dma_put_publication_path_browser_stop_condition`

## Findings

- Result: `pfifo_dma_put_publication_path_browser_stop_condition=dma-put-is-guest-nv-user-write-stream-idle-is-consumer-empty-gate`.
- `DMA_PUT` publication path:
  - `NV_USER_DMA_PUT` is defined as user-channel offset `0x40`.
  - `user_write()` handles `NV_USER_DMA_PUT` by writing `d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT] = val`.
  - The same branch calls `user_boot_trace_dma_put(...)`.
  - It then calls `pfifo_kick_with_source(d, "nv-user-dma-put")`, which sets `fifo_kick=true`, logs scheduler state if enabled, and broadcasts `fifo_cond`.
- Existing PUT marker:
  - `user_boot_trace_dma_put()` emits `BOOT_MARK b6 nv2a=user-dma-put ... old_dma_put=... new_dma_put=...`.
  - Its default limit is `XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 0`.
  - It is enabled only by `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT`; no browser fixture plumbing for that knob was found in `scripts` or `browser`.
  - The stable native/browser logs have no `nv2a=user-dma-put` markers.
- PFIFO pusher-empty decision:
  - `pfifo_run_pusher()` reads local `dma_get_v = *dma_get` and `dma_put_v = *dma_put` each loop.
  - If `dma_get_v == dma_put_v`, it logs `pusher-empty` and breaks.
  - After committing `*dma_get = dma_get_v`, it emits stream-idle transition only when the committed GET equals current PUT.
- Stream-idle definition:
  - `xemu_xbe_nv2a_wait_is_stream_idle()` requires wait source `pfifo-window`, op `pusher-empty`, known PFIFO state, and `dma_get == dma_put`.
  - Browser/headless timer pump readiness can use that stream-idle snapshot as a gate for modes such as ready-edge or after-PFIFO-empty.
  - This is a diagnostic/pump gate, not a strict dashboard-success condition.
- Scheduler behavior:
  - The PFIFO thread loops, runs `pgraph_process_pending()`, runs `pfifo_run_pusher()` when not halted, then waits on `fifo_cond` only if `fifo_kick` is false.
  - A later guest `NV_USER_DMA_PUT` write should kick the PFIFO thread via `pfifo_kick_with_source("nv-user-dma-put")`.
- Classification:
  - Browser reaching `GET==PUT==0x03881318` means PFIFO consumed all commands currently published to it.
  - Native's later `dma_put=0x0388f814/0x0388f888` must come from a later guest/user-channel PUT publication.
  - Current stable logs cannot say whether browser never performs that later `NV_USER_DMA_PUT` write or performs it after the current capture window, because the existing `nv2a=user-dma-put` marker is disabled by default and not fixture-plumbed for browser.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: the next actionable evidence field is PUT publication itself. The narrowest way to get it is to enable/plumb the existing `nv2a=user-dma-put` marker for the browser and compare native/browser PUT sequences, rather than changing PFIFO decode or rerunning broad diagnostics.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/263-dma-put-code-path-loop-check.md` requested this static code-path inspection.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said code ownership and stop conditions are the right mode while static code can still classify the publication boundary.
- If yes, process adjustment for next 2-3 turns: use existing `nv2a=user-dma-put` instrumentation, but do not add a new runtime branch until the loop check approves the exact field and plumbing.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether to plumb/enable `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` for browser fixtures and run one focused browser/native PUT-sequence comparison, or to inspect environment plumbing first.
