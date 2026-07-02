# 207. DMA_PUT Marker Perturbation Loop Check

## Purpose

Run the required loop check after the marker runtime failed preservation in `history/206-dma-put-runtime-preservation-regressed.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/206-dma-put-runtime-preservation-regressed.md`
- Source marker implementation:
  `hw/xbox/nv2a/user.c`

## Loop-Guard Fields

- `dma_put_marker_perturbation_risk`
- do not inspect `nv2a=user-dma-put` fields from the regressed artifact

## Findings

The sub-agent chose `revise`.

Allowed next step: perform one bounded static/source review of whether the `nv2a=user-dma-put` marker is too perturbing. Do not extract the regressed marker fields, do not rerun the runtime, and do not revise the marker yet.

Progress-method critique: this branch is near over-investment in marker coverage. The preservation guard worked: the run reached useful boot evidence but lost the post-service edge, so the marker cannot be treated as causal. The correction is to make this a branch-exit check, not another diagnostic loop.

The static review should inspect only the marker code shape for:

- expensive guest CPU context capture;
- logging volume;
- lock/state reads;
- placement after `DMA_PUT` and before PFIFO kick.

## Decision

Revise.

## Next Step

Perform one source-only perturbation review and record `dma_put_marker_perturbation_risk`. No runtime and no marker-field extraction from the regressed artifact.
