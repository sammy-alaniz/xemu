# 281 - Deferred DMA PUT Preservation Loop Check

## Purpose

Record the bounded loop check after preservation failed for the deferred DMA
PUT observer runtime in
`history/280-deferred-dma-put-runtime-preservation-regressed.md`.

## Commands

Sub-agent loop check via `multi_agent_v1.send_input` /
`multi_agent_v1.wait_agent`.

## Inputs / Artifacts

- `history/277-deferred-dma-put-runtime-loop-check.md`
- `history/279-deferred-dma-put-raw-runtime-loop-check.md`
- `history/280-deferred-dma-put-runtime-preservation-regressed.md`

## Loop-Guard Field

- `deferred_dma_put_observer_runtime_preservation`

## Findings

- The sub-agent agreed that preservation failed at the key guard:
  `missing-browser-post-edge`.
- It rejected marker extraction, cap tuning, or a second DMA PUT runtime.
- It classified the observer runtime branch as runtime-negative evidence.
- Because the observer is default-off, immediate code removal is not required.
- The only approved next step is static-only perturbation review.

## Progress-Method Critique

The sub-agent said the branch was useful up to the preservation gate because it
tested whether the missing DMA continuation could be observed without
disturbing stable CPU-flow shape. After the failed post-service edge, it is no
longer useful as causal evidence and is now at instrumentation-drag risk.

## Decision

Revise.

## Next Step

Run a static-only source/log review for
`deferred_dma_put_observer_perturbation_cause`. No runtime, marker extraction,
or cap tuning.
