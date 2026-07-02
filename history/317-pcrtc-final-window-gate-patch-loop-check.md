# 317 - pcrtc final-window gate patch loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/316-pcrtc-final-window-gate-static-patch.md`.

## Exact commands

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/315, history/316; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f88-fddd-78e1-9175-e6f8a4e6deef
  timeout_ms=300000
```

## Inputs and artifacts

- `AGENTS.md`
- `goal.md`
- `history/315-pcrtc-final-window-gate-loop-check.md`
- `history/316-pcrtc-final-window-gate-static-patch.md`
- Sub-agent:
  - id `019f1f88-fddd-78e1-9175-e6f8a4e6deef`
  - nickname `Anscombe`

## Loop-guard fields

- `pcrtc_final_window_gate_patch_integrity`
- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`

## Findings

The sub-agent reported that the work is not looping yet. This is still a
scoped progression from plan to static patch to buildability check. It becomes
looping only if the next runtime reconfirms `missing-xbe-executed-marker`
without moving `browser_pre_stream_vector_service_state` or naming a
final-window blocker.

The narrowest boundary-changing fact remains whether the patched mode can
create a pre-stream PCRTC vector-service window before PFIFO stream-idle. The
build does not change that runtime field, but it is the necessary integrity
step for the touched browser/WASM-gated C paths, prototypes, and smoke env
plumbing.

The sub-agent recommended killing broad PCRTC cadence, entry-ready immediate
PCRTC raise, host-pump count/placement, PIT/precommit, deferred DMA_PUT
observer, and before-interrupt scheduler paths as causal fixes. It recommended
keeping the native pre-stream `pcrtc/intr-clear` serviceability hypothesis and
keeping the revised one-shot final-window deterministic PCRTC semantics.

## Progress-Method Critique

The method still connects to strict dashboard execution because it targets the
missing browser pre-stream serviceable state that precedes the first
watched-read tick gap. Main-menu proof and game launch remain downstream, but
this is still on the required path.

The history and loop-check process is helping here by preventing immediate
runtime churn, but it should not expand further. The next two or three turns
should be build-only, history, then one targeted runtime if the build passes.

Process adjustment: after the first runtime, do not tune the gate unless the
blocker is one concrete predicate bug. Otherwise kill or revise the
final-window hypothesis.

## Decision

Continue.

## Next step

Run the Podman WASM build as `pcrtc_final_window_gate_patch_integrity`. If it
fails, fix only compile/link issues without changing semantics. If it passes,
write history and then run the required loop check before the one targeted
runtime.
