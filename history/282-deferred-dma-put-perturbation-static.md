# 282 - Deferred DMA PUT Perturbation Static

## Purpose

Perform the approved static-only closure review after the deferred DMA PUT
runtime failed preservation at the post-service edge.

## Commands

```sh
rg -n "BROWSER_DIAGNOSTIC_APPLY name=nv2a_user_dma_put_limit|trace_nv2a_user_dma_put_limit|BROWSER_RUNTIME_SMOKE|BROWSER_RUNTIME_EVIDENCE|DISPLAY_CAPTURE_EVIDENCE|DASHBOARD_SECTION_MAP|dashboard=xbe-executed|0x80030e84->0x80030f31" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

sed -n '1,240p' hw/xbox/nv2a/user.c
sed -n '240,380p' hw/xbox/nv2a/user.c

rg -n "nv2aUserDmaPutLimit|nv2a_user_dma_put_limit|XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT|trace_nv2a_user_dma_put_limit" \
  browser/xbox-boot/main.js \
  browser/xbox-boot/worker.js \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  hw/xbox/nv2a/user.c
```

## Inputs / Artifacts

- Raw browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- `hw/xbox/nv2a/user.c`
- Browser runtime plumbing files.

## Loop-Guard Field

- `deferred_dma_put_observer_perturbation_cause`

## Findings

- Activation plumbing worked: the deferred runtime log has
  `BROWSER_DIAGNOSTIC_APPLY name=nv2a_user_dma_put_limit value=16` and runtime
  summary fields show `trace_nv2a_user_dma_put_limit=16`.
- The stable baseline has the same main ready-edge-host4 knobs but no DMA PUT
  observer activation field.
- The C observer is default-off, caches config at NV2A init, and avoids CPU/XBE
  helper calls under `pfifo.lock`.
- The hot path still does extra work for enabled DMA PUT writes: it snapshots
  fields under `pfifo.lock`, then returns to `user_write`, unlocks, and performs
  synchronous `fprintf(stderr, ...)` before returning from the guest MMIO write.
- Because browser stderr/log emission is synchronous from the guest execution
  path, even deferred-after-unlock marker output can perturb the timing enough
  to lose the stable post-service edge.

## Decision

Treat the deferred DMA PUT observer runtime branch as negative/non-promotable
browser evidence. The activation plumbing is not the problem; the enabled
observer still changes timing in the browser. Since the observer is default-off,
the code can remain as quarantined opt-in diagnostics, but it should not be used
for causal B6 evidence without a separate asynchronous/non-logging design.

## Next Step

Run the required bounded loop check. Expected direction is to return to the
stable ready-edge-host4 baseline causality path rather than run more DMA PUT
marker experiments.
