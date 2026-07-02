# 284 - Stable Noninstrumented Causal Field Selection

## Purpose

Select the next B6 causal field after quarantining the deferred DMA PUT runtime
branch, using only existing stable ready-edge-host4 artifacts and no new
browser hot-path instrumentation.

## Commands

```sh
rg -n "command_stream|dma_get|dma_put|0x03881318|late PGRAPH|non-instrumented|stable_ready_edge|next causal|next field|pgraph command" \
  goal.md \
  history/258-pgraph-command-stream-helper.md \
  history/260-method-1710-continuation-static.md \
  history/262-dma-put-boundary-static.md \
  history/264-dma-put-code-path-static.md \
  history/282-deferred-dma-put-perturbation-static.md

ls scripts | rg 'xbox-.*(compare|classify|summary|edge|pgraph|pfifo|dma|command|boundary)'

rg -n "B6_CURRENT|result=|divergence=|next=" \
  scripts/xbox-b6-current-boundary.sh \
  scripts/xbox-pgraph-command-stream-compare.py \
  scripts/xbox-post-service-watch-edge-compare.py \
  scripts/xbox-pre-service-tick-gap-compare.py

sed -n '88,130p' goal.md

rg -n -m 40 "NV_USER|DMA_PUT|user-dma-put|CACHE1_DMA_PUT|nv2a=user-dma-put" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n -m 80 "stream-idle-boundary|kernel-loop-probe|dashboard=kernel-loop|wait_source|wait_op|dma_get=0x03881318|dma_put=0x03881318|dma_put=0x0388" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

## Inputs / Artifacts

- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Recent command-stream histories.

## Loop-Guard Field

- `stable_ready_edge_host4_next_noninstrumented_causal_field`

## Findings

- Existing command-stream evidence still says the browser consumes the early
  command stream and stops at `dma_get=dma_put=0x03881318`.
- Native later has a larger published command window, including
  `dma_put=0x0388f814` / `0x0388f888`, reaches method `0x1710`, and eventually
  reaches strict dashboard execution.
- No generic `NV_USER` / `DMA_PUT` write evidence is present in the stable logs,
  so the next non-instrumented step cannot be another direct PUT-writer
  extraction.
- Existing logs do contain `pfifo=stream-idle-boundary`,
  `dashboard=kernel-loop-probe`, wait-state, IRQ, timer, and DMA GET/PUT fields
  around the shared stream-idle point.

## Decision

Select `post_stream_idle_guest_producer_wait_state` as the next causal field.

This field should compare, from existing stable logs only, what the guest CPU
and NV2A wait state do after the shared stream-idle boundary at
`0x03881318`: whether browser remains in a wait/poll state with no command
producer progress while native transitions toward the later command
continuation.

## Next Step

Run the required bounded loop check. If approved, write a static reducer/helper
or use existing reducers to classify
`post_stream_idle_guest_producer_wait_state` without new runtime instrumentation.
