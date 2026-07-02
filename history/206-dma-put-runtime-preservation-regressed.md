# 206. DMA_PUT Runtime Preservation Regressed

## Purpose

Run preservation-first checks on the new DMA_PUT marker browser runtime before extracting or interpreting `nv2a=user-dma-put`.

## Commands

```sh
scripts/xbox-browser-runtime-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log

scripts/xbox-display-capture-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log

scripts/xbox-dashboard-section-map-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log
```

## Inputs and Artifacts

- Raw browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log`
- Combined browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log`
- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Loop-Guard Fields

- runtime preservation classification
- `nv_user_dma_put_writer_cpu_context` was intentionally not extracted

## Findings

Raw browser gates passed:

```text
BROWSER_RUNTIME_EVIDENCE result=pass ... boot_result=timeout
DISPLAY_CAPTURE_EVIDENCE result=pass ... hash=7b855cba55da71ce7cc0466df7293d99d3987896515e54660be8e2ab51ec24e3
DASHBOARD_SECTION_MAP_EVIDENCE result=pass ... mapped_entry_rows=1
COMBINE_DASHBOARD_XBE_READ_EVIDENCE result=pass ... context=browser-runtime
```

Strict B6 still failed at the expected strict marker:

```text
DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker
```

The pre-service tick gap remained the known browser-behind shape:

```text
PRE_SERVICE_TICK_GAP_COMPARE result=pass
divergence=browser-first-watch-read-before-catchup
first_watch_read_tick_delta=136
browser_first_watch_read_edge=0x80014f32->0x80030e84
browser_first_watch_read_value=0x00000000
browser_first_watch_read_ticks=0
browser_first_service_eip=0x80018c95
```

The post-service watch edge did not preserve the stable ready-edge host4 shape:

```text
POST_SERVICE_WATCH_EDGE_COMPARE result=fail
divergence=missing-browser-post-edge
browser_pre_edge=0x80014f32->0x80030e84
browser_pre_value=0x00000000
browser_pre_ticks=0
browser_post_edge=none
browser_stream_idle_count=3
```

## Decision

Classify this artifact as shape-regressed for the specific marker-causality question. The run still reaches useful B4/B5/read/load/entry-ready/section-map evidence, but it does not preserve the stable post-service watch edge, so the `nv2a=user-dma-put` marker must not be interpreted causally from this artifact.

## Next Step

Run the required loop check. The next decision should be whether to stop DMA_PUT marker runtime work and return to the stable pre-service CPU/tick boundary, or to perform only a static/source-level review of whether the marker itself is too perturbing.
