# DMA PUT Observability Revise Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to enable/plumb the existing `nv2a=user-dma-put` marker next.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest static summary: `history/264-dma-put-code-path-static.md`
- Prior loop check: `history/263-dma-put-code-path-loop-check.md`
- Referenced prior history from sub-agent: `history/206`, `history/208`, `history/210`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: no code change or runtime occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `dma_put_publication_observability_safe_path`

## Findings

- Result: revise.
- The sub-agent accepted the static classification from `history/264`.
- It rejected immediately plumbing/running `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` because prior history already classified a DMA_PUT marker runtime as perturbing/high-risk.
- It specifically referenced:
  - `history/206`: DMA_PUT marker runtime shape-regressed.
  - `history/208` / `history/210`: marker quarantined by default.
- Recommended next field:
  - `dma_put_publication_observability_safe_path`
- The next step must be static-only and decide whether the existing `nv2a=user-dma-put` marker can be made safe enough, or whether a different non-runtime/static source path is needed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: do not add fixture plumbing or run the DMA_PUT marker yet. First inspect the prior negative histories and the marker implementation safety, especially logging cost under PFIFO lock before kick.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: the proposed plumbing-plus-runtime path would repeat a known perturbing DMA_PUT marker branch.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still connects to strict dashboard execution, visible main-menu proof, and game launch, but re-enabling a high-risk marker would make the work too diagnostic-heavy.
- If yes, process adjustment for next 2-3 turns: require a static safety/design decision before any PUT marker plumbing or runtime; prove the observation path will not run expensive logging under PFIFO lock before kick.

## Next Step

- Narrow follow-up: statically inspect `dma_put_publication_observability_safe_path`.
