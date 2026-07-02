# 323 - pcrtc final-window BQL ownership loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/322-pcrtc-final-window-bql-ownership-static.md`.

## Command(s)

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/321, history/322; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f94-1aea-75b3-9d71-a982620af414
  timeout_ms=300000
```

## Inputs And Artifacts

- `AGENTS.md`
- `goal.md`
- `history/321-pcrtc-final-window-runtime-loop-check.md`
- `history/322-pcrtc-final-window-bql-ownership-static.md`
- Sub-agent:
  - id `019f1f94-1aea-75b3-9d71-a982620af414`
  - nickname `Franklin`

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pcrtc_final_window_irq_delivery_ownership`

## Findings

- Result: the sub-agent decided this is not looping and approved a scoped code
  change.
- Important marker/comparator lines:
  - Kill PFIFO-window tuning, pump-count changes, PCRTC mode changes,
    timer-limit changes, and runtime reruns before ownership is fixed.
  - Keep the missing browser pre-stream `pcrtc/intr-clear` vector `0x30`
    service hypothesis as upstream of the tick gap and strict dashboard
    execution.
  - Revise the final-window branch so IRQ mutation is BQL-owned instead of
    calling `nv2a_update_irq()` from the PFIFO thread while holding
    `d->pfifo.lock`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a loop check only.

## Decision

- Status: current
- Why:
  The next action targets one field,
  `pcrtc_final_window_irq_delivery_ownership`, and preserves the already-proven
  final-window candidate semantics. Runtime probing is not justified until
  after patch and build/static verification.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  Patch only the deterministic final-window PCRTC delivery path so it uses the
  existing local pattern: release `d->pfifo.lock`, take BQL, call the helper,
  release BQL, and re-lock PFIFO.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The IRQ ownership fix is still on the causal path to browser pre-stream
  service, tick accumulation, and `dashboard=xbe-executed`. The right next mode
  is code change followed only by build/static verification.
- If yes, process adjustment for next 2-3 turns:
  Require every action to name the exact lock/BQL ownership field it changes or
  verifies, and do not run browser/native runtime until the patched ownership
  path has been recorded and loop-checked.

## Next Step

- Narrow follow-up: patch only the final-window PCRTC delivery ownership path
  and verify with build/static checks before any runtime.
