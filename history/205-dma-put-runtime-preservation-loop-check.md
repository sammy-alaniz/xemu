# 205. DMA_PUT Runtime Preservation Loop Check

## Purpose

Run the required loop check after `history/204-dma-put-marker-runtime-raw.md` and before inspecting the raw runtime artifact.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- Raw browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/browser-runtime.log`
- Planned combined log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1-combined.log`

## Loop-Guard Fields

- preservation classification for the new runtime artifact
- `nv_user_dma_put_writer_cpu_context` remains uninspected until preservation is classified

## Findings

The sub-agent agreed that preservation checks are the correct next probes. Do not extract or interpret `nv2a=user-dma-put` first; the marker only matters if the run preserved the stable ready-edge host4 shape.

Progress-method critique: preservation-first remains the right control because it prevents treating a marker from a regressed run as causal.

Ordering correction:

- run cheap raw-log gates first: browser runtime evidence, display capture, and section map;
- combine read evidence;
- then run strict B6, pre-service tick gap, and post-service edge checks;
- marker extraction comes last.

## Decision

Continue.

## Next Step

Run the preservation checks only, combine the log, and classify the artifact as comparable or regressed before reading the DMA_PUT marker fields.
