# 327 - pcrtc final-window BQL build loop check

## Purpose

Record the required bounded sub-agent loop check after
`history/326-pcrtc-final-window-bql-build.md`.

## Command(s)

```text
multi_agent_v1.spawn_agent:
  agent_type=explorer
  model=gpt-5.5
  reasoning_effort=xhigh
  task=read AGENTS.md, goal.md, history/325, history/326; answer loop-check
       questions; include Progress-Method Critique; do not edit files

multi_agent_v1.wait_agent:
  target=019f1f99-3f60-7a72-9fc5-a6341e4f67b8
  timeout_ms=300000
```

## Inputs And Artifacts

- `AGENTS.md`
- `goal.md`
- `history/325-pcrtc-final-window-bql-patch-loop-check.md`
- `history/326-pcrtc-final-window-bql-build.md`
- Sub-agent:
  - id `019f1f99-3f60-7a72-9fc5-a6341e4f67b8`
  - nickname `Mill`

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `browser_pre_stream_vector_service_state`

## Findings

- Result: the sub-agent approved exactly one targeted browser runtime using the
  same final-window PCRTC command shape from `history/320`.
- Important marker/comparator lines:
  - The runtime is justified because `history/320` hit `bql_locked()` and
    `history/326` proves the ownership patch is build-safe.
  - Kill more build/static verification before runtime, PFIFO-window tuning,
    pump-count changes, PCRTC mode changes, timer-limit changes, and dashboard
    detector changes.
  - The post-run extraction should look only for `bql_locked()` abort presence,
    `browser_pre_stream_vector_service_state`, and preservation/regression of
    existing B4/B5/read/load/entry-ready evidence.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a loop check only.

## Decision

- Status: current
- Why:
  The next runtime targets one loop-guard field,
  `browser_pre_stream_vector_service_state`, after a build-safe ownership patch
  changed the condition that caused the previous abort.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  Run exactly one browser runtime with no knob changes from the final-window
  command. If it does not change or explain
  `browser_pre_stream_vector_service_state`, switch back to code inspection
  rather than running variants.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The metric still connects to strict dashboard execution because the missing
  browser pre-stream vector service is upstream of the first watched-read tick
  gap and strict `dashboard=xbe-executed`. This runtime is not rerun-heavy if
  held to one run after the code change.
- If yes, process adjustment for next 2-3 turns:
  Allow only the `history/320` final-window runtime, one history entry
  summarizing the result, then code inspection if the field does not move or a
  narrow follow-up only if it does.

## Next Step

- Narrow follow-up: run exactly one targeted browser runtime for the BQL-safe
  final-window PCRTC path. Do not tune PFIFO windows, pump counts, PCRTC modes,
  timer limits, or dashboard detector logic.
