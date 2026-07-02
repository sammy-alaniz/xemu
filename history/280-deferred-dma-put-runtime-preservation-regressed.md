# 280 - Deferred DMA PUT Runtime Preservation Regressed

## Purpose

Run preservation-first checks on the deferred DMA PUT observer browser runtime
before interpreting any `nv2a=user-dma-put` markers.

## Commands

```sh
scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log
```

## Inputs / Artifacts

- Raw browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-deferred-dma-put-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Loop-Guard Field

- `deferred_dma_put_observer_runtime_preservation`

## Findings

- Read-evidence combine passed for `context=browser-runtime`.
- Browser runtime evidence passed with `boot_result=timeout`.
- Display capture passed with browser framebuffer hash
  `87a8fa88aa56e5ef6519b08344bb3f8a02f872925b68ca0274f74fcae7f40776`.
- Dashboard section-map evidence passed with `sections=6`,
  `executable_sections=1`, and `mapped_entry_rows=1`.
- Strict dashboard-loaded evidence still failed at
  `missing-xbe-executed-marker`, as expected for non-B6 browser runs.
- Pre-service tick gap preserved the known high-level divergence:
  `browser-first-watch-read-before-catchup`, native first watched read at
  136 ticks, browser first watched read at 0 ticks.
- Post-service watch-edge preservation failed:
  `POST_SERVICE_WATCH_EDGE_COMPARE result=fail
  divergence=missing-browser-post-edge`.
- The browser reached the pre-edge `0x80014f32->0x80030e84` at 0 ticks, but no
  browser post-edge `0x80030e84->0x80030f31` was found.

## Decision

The artifact is shape-regressed relative to the stable ready-edge-host4
baseline. Per the loop-check branch rule, do not extract or interpret
`nv2a=user-dma-put` markers causally from this runtime.

## Next Step

Run the required bounded loop check. The likely decision is to quarantine this
observer runtime branch or revise with static review only; do not run a second
DMA PUT runtime without a new approved field.
