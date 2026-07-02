# 197. DMA_PUT Ordering Loop Check

## Purpose

Run the required bounded loop check after `history/196-first-nv-user-dma-put-cause-initial-inspection.md`, including the requested progress-method critique.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/196-first-nv-user-dma-put-cause-initial-inspection.md`
- `history/50-pfifo-kick-source-runtime.md`
- `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- `hw/xbox/nv2a/user.c`

## Loop-Guard Fields

- `first_nv_user_dma_put_after_opportunity_cause`
- Proposed next field:
  `first_nv_user_dma_put_ordering_context`

## Findings

The sub-agent found the proposed static extraction non-redundant. `history/50` already answered the kick source, but not the ordering context around that source. The narrower follow-up is to place the guest `NV_USER_DMA_PUT` publication relative to the last timer opportunity and determine whether existing markers expose CPU or ordering context.

Progress-method critique: the method is still plausibly converging because it follows the known chain from timer opportunities, to delayed PFIFO publication, to the browser being behind at the first watched read. The risk is overfitting to PFIFO internals after PFIFO has already been shown to be late.

The correction is to make this extraction a gate. If existing markers do not expose useful CPU or ordering context for the DMA_PUT write, stop mining PFIFO logs and select either a marker-coverage design or return to the stable pre-service CPU/tick boundary.

## Decision

Continue.

## Next Step

Inspect only the existing source-tag browser artifact around the last timer opportunity and first `kick_source=nv-user-dma-put`. Record line deltas, nearby CPU/context markers if present, and whether the cause is observable or marker coverage is missing. Do not run runtime, scheduler, pusher, PFIFO-window, timer-opportunity, or B3/B4/B5 diagnostics.
