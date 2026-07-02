# 283 - Deferred DMA PUT Branch Closure Loop Check

## Purpose

Record the bounded loop check after static perturbation closure in
`history/282-deferred-dma-put-perturbation-static.md`.

## Commands

Sub-agent loop check via `multi_agent_v1.send_input` /
`multi_agent_v1.wait_agent`.

## Inputs / Artifacts

- `history/280-deferred-dma-put-runtime-preservation-regressed.md`
- `history/281-deferred-dma-put-preservation-loop-check.md`
- `history/282-deferred-dma-put-perturbation-static.md`

## Loop-Guard Field

- `deferred_dma_put_observer_perturbation_cause`

## Findings

- The sub-agent said the DMA PUT observer branch should stop as a runtime path.
- It accepted the static cause classification: deferred-after-unlock
  `fprintf(stderr, ...)` still runs synchronously on the browser guest MMIO path
  and can perturb timing enough to lose the stable post-service edge.
- No immediate code removal is required because the observer is default-off and
  opt-in.
- The branch is now classified as runtime-negative and non-promotable.

## Progress-Method Critique

The sub-agent said this branch was useful only up to the preservation gate. It
tested whether the missing DMA continuation could be observed safely, but after
shape regression it cannot support B6 causality. Continuing it would be
instrumentation drag.

## Decision

Continue, but not on the DMA PUT runtime branch.

## Next Step

Select the next non-instrumented causal field from the stable ready-edge-host4
baseline. The field is
`stable_ready_edge_host4_next_noninstrumented_causal_field`.
