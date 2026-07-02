# 313 - native pre-stream serviceable loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/312-native-pre-stream-serviceable-design-proposal.md`. The check also
includes the requested progress-method critique.

## Exact commands

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/312; answer loop-check questions;
       include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f7d-e955-7d00-8938-4f0874f340ba
  timeout_ms=300000
```

## Inputs and artifacts

- `AGENTS.md`
- `goal.md`
- `history/312-native-pre-stream-serviceable-design-proposal.md`
- Sub-agent:
  - id `019f1f7d-e955-7d00-8938-4f0874f340ba`
  - nickname `Locke`

## Loop-guard fields

- `native_pre_stream_serviceable_state_browser_mapping`
- `browser_pre_stream_vector_service_state`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Findings

The sub-agent reported that the current step is not looping. The previous work
had loop risk around pump/vblank variants, but history/312 narrowed the
question to one serviceability gap: native has a pre-stream
`pcrtc/intr-clear` vector-service window and browser does not.

The narrowest next fact is whether a default-off browser mode can expose one
PCRTC vblank serviceable state before PFIFO stream-idle at the stable
final-window/ready-edge boundary, without enabling normal vblank cadence or
losing B4/B5, vector `0x30`, IRET, stream-idle, and the post-service watch
edge.

The sub-agent recommended killing host-pump count increases, broad normal
PCRTC vblank, precommit/PIT/pump-placement reruns, and promotion of the
deterministic-PCRTC prestream branch as-is. It recommended keeping the
serviceability hypothesis and revising the PCRTC gate so it is not just
"turn vblank back on"; it should be a single state-verified availability gate
that lets the guest clear the interrupt naturally and logs enough to classify
`browser_pre_stream_vector_service_state`.

## Progress-Method Critique

The sub-agent judged the method still connected to strict dashboard execution
because it targets the pre-service tick/serviceability gap blocking
`dashboard=xbe-executed`. Main-menu and game-launch proof remain downstream but
depend on this prerequisite.

It also judged the broader work historically too diagnostic-heavy. The current
static-planning mode is a useful correction, but the next two or three turns
should not produce more critique without a concrete patch plan.

Recommended process adjustment: allow only one static plan, one patch, and one
runtime attempt tied to `browser_pre_stream_vector_service_state`; do not add a
new comparator family unless that field moves.

## Decision

Continue.

## Next step

Create a no-runtime static patch plan with an acceptance matrix: exact gate
predicates, source state for each predicate, marker fields, preservation gates,
and failure criteria. The planned field remains
`native_pre_stream_serviceable_state_browser_mapping`, with secondary planned
measurement of `browser_pre_stream_vector_service_state`.
