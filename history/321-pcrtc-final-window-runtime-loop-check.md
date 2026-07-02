# 321 - pcrtc final-window runtime loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/320-pcrtc-final-window-runtime.md`.

## Command(s)

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/319, history/320; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f91-5f06-7210-9f23-1b3f273c9e26
  timeout_ms=300000
```

## Inputs And Artifacts

- `AGENTS.md`
- `goal.md`
- `history/319-pcrtc-final-window-gate-build-loop-check.md`
- `history/320-pcrtc-final-window-runtime.md`
- Sub-agent:
  - id `019f1f91-5f06-7210-9f23-1b3f273c9e26`
  - nickname `Singer`

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pcrtc_final_window_irq_delivery_ownership`
  and `browser_pre_stream_vector_service_state`

## Findings

- Result: the sub-agent decided this is not looping because `history/320`
  changed the boundary from gate timing to IRQ delivery ownership.
- Important marker/comparator lines:
  - Kill PFIFO-window tuning: the final-window gate already fired at
    `dma_get_before=0x03881314`, `dma_get_after=0x03881318`,
    `dma_put=0x03881318`, with `entry_ready=yes` and `stream_idle_seen=no`.
  - Keep the missing browser pre-stream PCRTC/vector `0x30` service state as
    the right B6 prerequisite.
  - Revise the branch around BQL/thread ownership for IRQ mutation.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: the approved next mode is code inspection first, then a narrow code
  change only if the BQL-safe delivery path is clear.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  Inspect the IRQ assertion call path and identify whether the final-window
  callback is running outside BQL. Choose either a BQL-owned deferred delivery
  path or a correct lock acquisition point according to local QEMU ownership
  rules.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The metrics still connect to strict dashboard execution because the missing
  browser pre-stream vector service is upstream of the first-watch-read tick
  gap and strict `dashboard=xbe-executed`. The work is diagnostic-heavy but
  `history/320` produced a new ownership failure, not a useless rerun. The
  right next mode is code inspection, not runtime probing.
- If yes, process adjustment for next 2-3 turns:
  Require every action to answer only: where should the final-window PCRTC IRQ
  be delivered so `cpu_interrupt()` runs with valid BQL ownership?

## Next Step

- Narrow follow-up: inspect the PCRTC final-window IRQ assertion path and the
  existing QEMU/xemu BQL-safe IRQ delivery patterns. Do not tune PFIFO windows,
  pump counts, PCRTC vblank modes, or timer limits.
