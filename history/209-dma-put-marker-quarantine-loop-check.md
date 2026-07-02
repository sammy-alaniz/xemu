# 209. DMA_PUT Marker Quarantine Loop Check

## Purpose

Run the required loop check after `history/208-dma-put-marker-perturbation-review.md` and before making any quarantine code change.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/208-dma-put-marker-perturbation-review.md`
- Source file:
  `hw/xbox/nv2a/user.c`

## Loop-Guard Fields

- `dma_put_marker_perturbation_risk`
- `dma_put_marker_default_quarantined`

## Findings

The sub-agent approved the quarantine code change as allowed and non-redundant. The preservation guard failed, the source review found a plausible perturbation path, and the current default would let the marker affect future runs accidentally.

Progress-method critique: disabling the marker by default corrects the over-investment risk while preserving the code context for later explicitly opted-in use. It protects the stable ready-edge host4 baseline from a marker that logs under `pfifo.lock` before the PFIFO kick.

Process correction:

- after the build-only quarantine, stop DMA_PUT marker work;
- return to the stable pre-service CPU/tick boundary;
- do not rerun the marker runtime.

## Decision

Continue.

## Next Step

Change only `XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT` to `0` for browser and native builds, run build verification only, write history, then loop-check before selecting the next stable-baseline target.
