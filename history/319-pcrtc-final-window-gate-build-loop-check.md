# 319 - pcrtc final-window gate build loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/318-pcrtc-final-window-gate-wasm-build.md`.

## Exact commands

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/317, history/318; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f8b-9cf7-72c3-8b20-aa662ca183fb
  timeout_ms=300000
```

## Inputs and artifacts

- `AGENTS.md`
- `goal.md`
- `history/317-pcrtc-final-window-gate-patch-loop-check.md`
- `history/318-pcrtc-final-window-gate-wasm-build.md`
- Sub-agent:
  - id `019f1f8b-9cf7-72c3-8b20-aa662ca183fb`
  - nickname `Avicenna`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `pcrtc_final_window_gate_patch_integrity`
- `native_pre_stream_serviceable_state_browser_mapping`

## Findings

The sub-agent reported that the work is not looping yet. The build was a
necessary integrity gate after a scoped default-off patch. It becomes looping
only if the next runtime reconfirms `missing-xbe-executed-marker` without
changing or explaining `browser_pre_stream_vector_service_state`.

The narrowest next fact is whether
`XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM=1` creates a browser
pre-stream PCRTC/vector `0x30` service window before PFIFO stream-idle while
preserving B4/B5, dashboard read/load/entry-ready, stream-idle, IRET, and the
post-service watch edge.

The proposed runtime was judged justified because it names one field and tests
the built patch's only meaningful runtime claim.

## Progress-Method Critique

The method is still moving toward strict dashboard execution because it targets
the missing browser pre-stream service state tied to the first watched-read
tick gap. Main-menu visibility and game launch remain downstream, but this
field is still on the required path.

The work is diagnostic-heavy, but this runtime is justified because it follows
a concrete patch and has a single named field. The next step should stay
one-shot: after the runtime, either promote only if boundary preservation
improves, or kill/revise the final-window PCRTC hypothesis after one concrete
predicate analysis.

## Decision

Continue.

## Next step

Run exactly one targeted browser runtime with
`XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM=1`, judging
`browser_pre_stream_vector_service_state`, preservation of
B4/B5/read/load/entry-ready/stream-idle/vector/IRET/post-service watch edge,
and strict B6 without weakening the checker.
