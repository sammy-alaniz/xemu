# 315 - pcrtc final-window gate loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/314-pcrtc-final-window-gate-static-plan.md`.

## Exact commands

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/313, history/314; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f83-4952-7bd3-b0be-74d29f155d72
  timeout_ms=300000
```

## Inputs and artifacts

- `AGENTS.md`
- `goal.md`
- `history/313-native-pre-stream-serviceable-loop-check.md`
- `history/314-pcrtc-final-window-gate-static-plan.md`
- Sub-agent:
  - id `019f1f83-4952-7bd3-b0be-74d29f155d72`
  - nickname `Bacon`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Findings

The sub-agent reported that this step is not looping. The plan narrows the
question to one missing state: whether browser can create the native-like
pre-stream `pcrtc/intr-clear` vector-service window before PFIFO stream-idle.

The narrowest next fact is whether the default-off final-window gate changes
`browser_pre_stream_vector_service_state` from no equivalent pre-stream state
to either a real pre-stream vector `0x30` service after PCRTC clear, or a named
blocker explaining why that state cannot occur.

The sub-agent recommended killing broad normal-vblank, entry-ready PCRTC raise,
host-pump count/placement, PIT/precommit reruns, and the quarantined
before-interrupt scheduler path. It recommended keeping the native pre-stream
serviceability hypothesis and revising deterministic PCRTC pre-stream semantics
to mean exactly one real PCRTC vblank at the verified final PFIFO one-word
window.

The final-window PCRTC gate was judged meaningfully narrower than rejected
PCRTC paths because it is default-off, one-shot, PFIFO-final-word gated, and
uses a real PCRTC pending/IRQ path instead of normal cadence or host pumping.

## Progress-Method Critique

The sub-agent judged that the method still points toward strict dashboard
execution because it targets the pre-stream timing/serviceability gap blocking
browser `dashboard=xbe-executed`. Main-menu proof and game launch remain
downstream but depend on this prerequisite.

The work is no longer too rerun-heavy at this moment. It has shifted from
runtime probes to a constrained causal patch. The next two or three turns
should be patch, one runtime, and history summary.

Process adjustment: after the first run, accept only field movement or a named
blocker; do not tune the gate unless the blocker is a single concrete predicate
bug. Treat "or proves why this cannot happen" as a one-shot negative
classification, not an acceptable steady state.

## Decision

Continue.

## Next step

Implement the scoped default-off final-window PCRTC availability gate, with
explicit allow/fail marker reasons. Then run exactly one strict runtime probe
for `browser_pre_stream_vector_service_state`.
