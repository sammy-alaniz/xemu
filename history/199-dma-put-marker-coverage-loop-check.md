# 199. DMA_PUT Marker Coverage Loop Check

## Purpose

Run the required loop check after `history/198-first-nv-user-dma-put-ordering-context.md`, including progress-method critique before any code change.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/198-first-nv-user-dma-put-ordering-context.md`
- `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- `hw/xbox/nv2a/user.c`
- `hw/xbox/nv2a/pfifo.c`

## Loop-Guard Fields

- `nv_user_dma_put_writer_cpu_context`
- `first_nv_user_dma_put_writer_marker_coverage`

## Findings

The sub-agent found the proposed step non-redundant only as a final marker-coverage step. The PFIFO-side cause is already answered: no DMA work exists during the opportunity window, then guest `NV_USER_DMA_PUT` publishes work later.

Progress-method critique: this remains convergent only if it is treated as a narrow handoff from PFIFO timing back to CPU/tick ordering. The risk is adding markers without changing the boundary.

The guard is strict:

- add one marker-only patch;
- perform one build only;
- write history;
- run another loop check before any runtime;
- do not change PFIFO behavior, scheduling, timer delivery, B6 success rules, or broad marker limits;
- if a later runtime does not preserve the stable B4/B5/read/load/entry-ready/section-map/post-service-edge shape, do not interpret the marker causally;
- if the marker only says "guest writes late" without actionable CPU/tick context, stop PFIFO instrumentation and return to the stable pre-service CPU/tick boundary.

## Decision

Continue.

## Next Step

Add only an `NV_USER_DMA_PUT` diagnostic marker in `hw/xbox/nv2a/user.c`, logging old/new DMA_PUT, DMA_GET, channel, source, and guest CPU context if cheaply available. Then build only, write history, and run the next loop check before any runtime.
