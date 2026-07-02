# 329 - pcrtc final-window BQL runtime loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/328-pcrtc-final-window-bql-runtime.md`.

## Command(s)

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/327, history/328; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f9f-defe-74a1-ae24-60a092c8386a
  timeout_ms=300000
```

## Inputs And Artifacts

- `AGENTS.md`
- `goal.md`
- `history/327-pcrtc-final-window-bql-build-loop-check.md`
- `history/328-pcrtc-final-window-bql-runtime.md`
- Sub-agent:
  - id `019f1f9f-defe-74a1-ae24-60a092c8386a`
  - nickname `Dirac`

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pcrtc_irq_pending_but_no_pre_stream_vector_service`

## Findings

- Result: the sub-agent approved code/log-order inspection only.
- Important marker/comparator lines:
  - The last run changed the boundary from `bql_locked()` abort to
    `pcrtc-final-window-irq-pending-at-transition-not-serviced`.
  - Kill more final-window/PFIFO/timer-limit tuning before explaining delivery
    ordering.
  - Keep that PCRTC IRQ pending at transition is real and BQL-safe.
  - Revise the hypothesis from "asserting PCRTC IRQ at the final PFIFO window
    is sufficient" to "asserting PCRTC IRQ is necessary but not sufficient;
    CPU interrupt delivery must be scheduled/observed before stream-idle
    continuation or guest clear."
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a loop check only.

## Decision

- Status: current
- Why:
  The next step targets `browser_pre_stream_vector_service_state` directly and
  does not rerun broad B3/B4/B5, timer, PFIFO-window, or PCRTC-mode probes.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  Do a bounded code/log-order trace inspection that can change or explain why
  `pending_interrupt=yes cpu_exit_request=yes` does not lead to a pre-stream
  vector/IRET marker.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The metric still connects to strict dashboard execution because the missing
  pre-stream interrupt service is upstream of the watched-word tick gap and
  strict `dashboard=xbe-executed`. The work is close to becoming
  diagnostic-heavy, so more runtime variants now would be rerun-heavy.
- If yes, process adjustment for next 2-3 turns:
  Require every inspected call path to answer one ordering question:
  IRQ asserted -> CPU interrupt request -> CPU exit/resume -> vector service
  marker -> guest PCRTC clear.

## Next Step

- Narrow follow-up: inspect code/log ordering only for
  `pcrtc_irq_pending_but_no_pre_stream_vector_service`. Do not run another
  browser runtime or tune the final-window gate.
