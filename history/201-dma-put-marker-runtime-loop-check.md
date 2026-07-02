# 201. DMA_PUT Marker Runtime Loop Check

## Purpose

Run the required loop check after the marker-only build in `history/200-nv-user-dma-put-marker-build.md`, including progress-method critique before any runtime.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/198-first-nv-user-dma-put-ordering-context.md`
- `history/200-nv-user-dma-put-marker-build.md`
- `hw/xbox/nv2a/user.c`
- Stable browser baseline shape:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Fields

- `nv_user_dma_put_writer_cpu_context`
- preservation of B4/B5/read/load/entry-ready/section-map/post-service-edge shape

## Findings

The sub-agent found that one runtime is justified. The marker is built, marker-only, and answers a field existing logs cannot answer: the exact guest writer context for `NV_USER_DMA_PUT`.

Progress-method critique: this has a concrete field and a bounded stop condition. It should not become another diagnostic loop if the next step is exactly one stable ready-edge host4-shaped browser runtime, adding only `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` as needed.

The required guard:

- first require B4/B5/read/load/entry-ready/section-map and post-service-edge comparability;
- if the run shape regresses, classify it as non-causal and do not interpret DMA_PUT context;
- if it preserves shape, extract only `nv2a=user-dma-put` writer EIP/CPU state relative to the timer-opportunity window and first watched read;
- do not rerun old scheduler, pusher, PFIFO-window, timer-opportunity, or broad B3/B4/B5 diagnostics.

## Decision

Continue.

## Next Step

Run one focused browser runtime from the stable baseline shape with the new marker enabled, then combine/check strict B6 and preservation gates before analyzing the marker.
