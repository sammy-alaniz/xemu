# 277 - Deferred DMA PUT Runtime Loop Check

## Purpose

Record the bounded loop check after activation plumbing build verification in
`history/276-deferred-dma-put-activation-plumbing-build-pass.md`.

## Commands

Sub-agent loop check via `multi_agent_v1.send_input` /
`multi_agent_v1.wait_agent`.

## Inputs / Artifacts

- `history/274-deferred-dma-put-activation-plumbing-static.md`
- `history/275-deferred-dma-put-activation-plumbing-loop-check.md`
- `history/276-deferred-dma-put-activation-plumbing-build-pass.md`

## Loop-Guard Field

- `deferred_dma_put_observer_activation_plumbing_build_status`

## Findings

- The sub-agent found that the activation plumbing plus static/build checks are
  sufficient to allow exactly one browser runtime.
- The next field is `deferred_dma_put_observer_runtime_preservation`.
- Runtime interpretation is allowed only if the run preserves browser runtime
  evidence, display capture, dashboard read/load/entry-ready, section-map,
  PFIFO stream-idle, comparable vector `0x30` service/IRET/post-service
  watch-edge shape, and strict B6 semantics.
- DMA PUT markers must not be treated as dashboard execution.

## Progress-Method Critique

The sub-agent said the runtime is justified but barely: it is still
instrumentation-heavy, but it can answer one concrete fact now that unsafe
placement and non-activation have been addressed. It also set a strict branch
exit rule: one capped runtime only.

## Decision

Continue.

## Next Step

Run one ready-edge-host4-shaped browser runtime with a small
`XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` cap and evaluate preservation before
interpreting any DMA PUT marker order.
