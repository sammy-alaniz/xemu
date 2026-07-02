# Deferred DMA PUT Design Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue after classifying the current DMA_PUT marker as unsafe.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest static summary: `history/266-dma-put-observability-safety-static.md`
- Prior loop check: `history/265-dma-put-observability-revise-loop-check.md`
- Fixture assumptions: no code change or runtime occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `deferred_dma_put_observer_design_safe_enough`

## Findings

- Result: continue, but only with static design.
- The sub-agent rejected guest CPU-flow inspection for now because the current boundary says the missing fact is PUT publication and existing logs cannot observe it.
- The sub-agent rejected running or plumbing the current marker as-is.
- Recommended next field:
  - `deferred_dma_put_observer_design_safe_enough`
- Required design properties:
  - cheap snapshot under `pfifo.lock`,
  - kick and unlock before emission,
  - deferred capped emission outside the lock,
  - no CPU state capture,
  - no environment/file initialization in the hot path,
  - opt-in default off,
  - preservation-gated future runtime.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: write a static minimal observer design before any code edit or runtime.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: option A is the only acceptable continuation, but it must be static design only.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still connects to strict dashboard execution, visible main-menu proof, and game launch because the missing later DMA PUT leads to native's `0x1710` continuation and then strict dashboard execution. But the work is very diagnostic-heavy now.
- If yes, process adjustment for next 2-3 turns: before any observer code or runtime, require a written minimal design proving the observer does not log or call helpers under `pfifo.lock` and has a hard preservation gate.

## Next Step

- Narrow follow-up: statically design `deferred_dma_put_observer_design_safe_enough`.
