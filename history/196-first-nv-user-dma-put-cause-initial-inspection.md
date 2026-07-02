# 196. First NV_USER DMA_PUT Cause Initial Inspection

## Purpose

Identify the one new field `first_nv_user_dma_put_after_opportunity_cause` without launching another browser runtime. The aim was to explain what the already-known `first_kick_after_last_opportunity_source=nv-user-dma-put` means at the source-code level, and whether it points at PFIFO scheduling or guest-side publication ordering.

## Commands

```sh
sed -n '70,125p' hw/xbox/nv2a/user.c
sed -n '1140,1410p' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
rg -n 'headless=timer-opportunity|pfifo=scheduler|pfifo=progress|pfifo=window|nv-user-dma-put|dma_get=0x03880000|read_lba=4609|dashboard=xbe-loaded|dashboard=xbe-entry-probe' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log | sed -n '1,220p'
rg -n 'NV_USER_DMA_PUT|DMA_PUT|nv-user-dma-put|pfifo_kick_with_source|pfifo=progress|pfifo=scheduler' history/50-pfifo-kick-source-runtime.md history/51-pfifo-dma-put-loop-check.md history/40-pfifo-window-publication-classifier.md history/42-pfifo-pusher-entry-classifier.md
```

## Inputs and Artifacts

- Existing focused source-tag artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- Existing history:
  `history/50-pfifo-kick-source-runtime.md`
- Source file:
  `hw/xbox/nv2a/user.c`

## Loop-Guard Fields

- `first_nv_user_dma_put_after_opportunity_cause`
- Existing known field from history:
  `first_kick_after_last_opportunity_source=nv-user-dma-put`

## Findings

The source-level inspection of `hw/xbox/nv2a/user.c` showed that `nv-user-dma-put` is emitted from the `NV_USER_DMA_PUT` case in `user_write()`. When the guest writes that register for the current DMA channel, xemu stores the value in `NV_PFIFO_CACHE1_DMA_PUT`, tags the kick as `nv-user-dma-put`, and calls `pfifo_kick_with_source()`.

This means the first post-opportunity PFIFO scheduler kick is not a delayed anonymous PFIFO thread wakeup. It is caused by a guest NV_USER MMIO write publishing a new DMA PUT pointer for PFIFO work.

The larger log/history extraction commands produced output too large for the visible transcript after compaction. The useful confirmed result from this inspection is therefore the source-level meaning of the source tag, not a complete timeline around lines 1162-1385.

## Decision

Do not run a new runtime for this field. The first-order answer is available statically: `nv-user-dma-put` means guest-side DMA command publication through `NV_USER_DMA_PUT`, followed by a PFIFO kick. The next step should be a tighter static extraction from the existing source-tag artifact to place that first DMA_PUT kick against the last timer opportunity and to see whether existing markers expose any guest CPU context near the write.

## Next Step

Run the required bounded loop check, including progress-method critique, then continue with a narrow static extraction only. The next proposed field is `first_nv_user_dma_put_ordering_context`.
