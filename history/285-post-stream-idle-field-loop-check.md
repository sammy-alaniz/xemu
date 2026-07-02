# 285 - Post-Stream-Idle Field Loop Check

## Purpose

Record the bounded loop check after selecting
`post_stream_idle_guest_producer_wait_state` in
`history/284-stable-noninstrumented-causal-field-selection.md`.

## Commands

Sub-agent loop check via `multi_agent_v1.send_input` /
`multi_agent_v1.wait_agent`.

## Inputs / Artifacts

- `history/283-deferred-dma-put-branch-closure-loop-check.md`
- `history/284-stable-noninstrumented-causal-field-selection.md`

## Loop-Guard Field

- `stable_ready_edge_host4_next_noninstrumented_causal_field`

## Findings

- The sub-agent approved
  `post_stream_idle_guest_producer_wait_state` as the next non-instrumented
  field.
- It said the field targets the current causal gap: browser reaches
  stream-idle at `dma_get=dma_put=0x03881318`, while native later publishes
  more command work and reaches strict dashboard execution.
- The next action must be static only: a focused reducer over existing stable
  logs.
- No PFIFO-window, pusher, scheduler, timer-opportunity, B3/B4/B5, browser
  runtime, or new marker work is allowed for this step.

## Progress-Method Critique

The sub-agent said this returns us toward B6 progress after the DMA PUT detour
because it asks what the stable browser does after the point where native
continues toward late PGRAPH handoff and strict `dashboard=xbe-executed`.

## Decision

Continue.

## Next Step

Classify `post_stream_idle_guest_producer_wait_state` from existing stable logs
only.
