# 325 - pcrtc final-window BQL patch loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/324-pcrtc-final-window-bql-ownership-patch.md`.

## Command(s)

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/323, history/324; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f96-e03c-7300-b496-314ef1de6629
  timeout_ms=300000
```

## Inputs And Artifacts

- `AGENTS.md`
- `goal.md`
- `history/323-pcrtc-final-window-bql-ownership-loop-check.md`
- `history/324-pcrtc-final-window-bql-ownership-patch.md`
- Sub-agent:
  - id `019f1f96-e03c-7300-b496-314ef1de6629`
  - nickname `Faraday`

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pcrtc_final_window_irq_delivery_ownership`

## Findings

- Result: the sub-agent approved build/static verification only.
- Important marker/comparator lines:
  - The next fact is whether `pcrtc_final_window_irq_delivery_ownership` is
    build-safe after the PFIFO lock release, BQL acquire, PCRTC raise, BQL
    release, and PFIFO re-lock sequence.
  - Kill PFIFO-window tuning, pump-count changes, PCRTC mode changes,
    timer-limit changes, and dashboard detector changes as next steps.
  - No runtime experiment is justified before build/static verification.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a loop check only.

## Decision

- Status: current
- Why:
  `git diff --check` plus the existing Podman WASM build is narrow,
  non-runtime, and tied to `pcrtc_final_window_irq_delivery_ownership`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  The ownership/locking precondition must pass build/static checks before any
  further runtime probing or code tuning.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  This still connects to strict dashboard execution because browser pre-stream
  vector service is upstream of the watched-word tick gap and strict
  `dashboard=xbe-executed`. The process is helping by preventing another broad
  PCRTC/PFIFO/timer rerun.
- If yes, process adjustment for next 2-3 turns:
  Allow only actions that verify or preserve
  `pcrtc_final_window_irq_delivery_ownership` until the build result is
  recorded.

## Next Step

- Narrow follow-up: run `git diff --check` and the existing Podman WASM build
  for the ownership patch. Do not run browser/native runtime before recording
  the build result and running the next loop check.
