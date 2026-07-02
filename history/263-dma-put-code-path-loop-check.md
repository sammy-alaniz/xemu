# DMA PUT Code Path Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue from the DMA PUT boundary static result and what code path to inspect.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest static summary: `history/262-dma-put-boundary-static.md`
- Prior loop check: `history/261-dma-put-continuation-loop-check.md`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: no code change or runtime occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `pfifo_dma_put_publication_path_browser_stop_condition`

## Findings

- Result: continue.
- The sub-agent accepted that browser consumes available commands and reaches pusher-empty; the missing fact is upstream publication of the native continuation after `0x03881318`.
- Recommended next field:
  - `pfifo_dma_put_publication_path_browser_stop_condition`
- Static inspection should answer:
  - where `DMA_PUT` is read/published,
  - what code decides pusher-empty/stream-idle at `GET==PUT`,
  - and whether browser-specific host/runtime stop conditions can leave the guest before it submits the native `dma_put=0x0388f814` / `0x0388f888` continuation.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: continue with narrow static code inspection only; no new markers, runtime, old classifier reruns, or broad graphics stack review unless static code cannot classify the publication boundary.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the proposed action is a narrow static code inspection of the DMA PUT publication path, not a rerun of old PFIFO classifiers.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still moves toward strict dashboard execution, visible main-menu proof, and game launch because the missing DMA continuation leads to the native late `0x1710` regime and then `dashboard=xbe-executed`. We are diagnostic-heavy, but still not rerun-heavy.
- If yes, process adjustment for next 2-3 turns: inspect code ownership and stop conditions only; no new markers or runtime unless static code cannot classify the publication boundary.

## Next Step

- Narrow follow-up: statically inspect `pfifo_dma_put_publication_path_browser_stop_condition`.
