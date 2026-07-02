# 297 - PCRTC Service Design Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether a design-only deterministic PCRTC pre-stream service plan is the next
  justified mode after `history/296`.

## Command(s)

```sh
# Bounded sub-agent loop check via multi_agent_v1.spawn_agent/wait_agent.
# The prompt required `Progress-Method Critique` and prohibited runtime,
# instrumentation, code changes, old normal-vblank/pcrtc-prestream-host/PIT/
# scheduler/precommit/before-interrupt/DMA_PUT branches, and weakened B6
# criteria.
```

## Inputs And Artifacts

- Updated goal file: `goal.md`
- Input histories:
  - `history/295-goal-update-loop-check.md`
  - `history/296-browser-pre-stream-vector-service-state-inspection.md`
- Output directory/log: none; sub-agent critique only.
- Fixture assumptions: none.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `next_design_decision`

## Findings

- Result: continue.
- Important marker/comparator lines:
  - The sub-agent accepted the classification
    `browser_pre_stream_vector_service_state=blocked-by-pcrtc-vblank-suppression-and-pfifo-empty-gated-timer-readiness`.
  - Loop guard named by the sub-agent:
    `browser_pre_stream_vector_service_state`.
  - Allowed next action:
    draft one design-only patch plan for a default-off deterministic PCRTC
    pre-stream service mode.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; no runtime or static comparator was run.

## Decision

- Status: current
- Why:
  The next action remains design-only. The plan must name the exact state
  predicate, ownership functions, gating conditions, preserved ready-edge host4
  invariants, and review criteria before any code or runtime.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  The proposed step targets the missing pre-stream PCRTC serviceable state
  without starting another runtime or reviving old pump/vblank branches.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  This continues narrowing causality from generic timing to the absent
  `pcrtc/vblank-raise -> pcrtc/intr-clear -> vector 0x30 service` state,
  preserves strict B6, and improves determinism by designing an emulated-state
  gate rather than using browser wall-clock cadence.
- If yes, process adjustment for next 2-3 turns:
  Draft the design plan only. Do not code or run until the design has a named
  predicate and preservation checks.

## Next Step

- Narrow follow-up:
  Draft the deterministic PCRTC pre-stream service patch plan.
