# 203. DMA_PUT Runtime Command Loop Check

## Purpose

Run the required loop check after `history/202-dma-put-runtime-command-prep.md` and before launching the one authorized browser runtime.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/202-dma-put-runtime-command-prep.md`
- Planned output directory:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/`
- Stable ready-edge host4 baseline shape from `history/50-pfifo-kick-source-runtime.md`

## Loop-Guard Fields

- `nv_user_dma_put_writer_cpu_context`
- ready-edge host4 runtime shape preservation

## Findings

The sub-agent found that the prepared command still supports the single-runtime plan. It reuses the known ready-edge host4 shape and adds only:

```text
XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT=16
```

Progress-method critique: preservation-first analysis is sufficient if enforced strictly. First confirm browser runtime evidence, display capture, combined dashboard read/load/entry-ready/section-map, pre-service tick-gap comparability, and post-service watch-edge comparability. If those fail, record the run as shape-regressed and do not interpret `nv2a=user-dma-put` causally. If they pass, extract only the DMA_PUT writer CPU fields and line/order relative to the last timer opportunity and first watched read.

## Decision

Continue.

## Next Step

Run exactly one prepared ready-edge host4 browser runtime into the new artifact directory, with only the DMA_PUT marker limit added. Then write history before any further probe or code change.
