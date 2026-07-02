# 287 - Post-Stream-Idle Reducer Loop Check

## Purpose

Record the bounded loop check after the
`post_stream_idle_guest_producer_wait_state` reducer in
`history/286-post-stream-idle-guest-producer-reducer.md`.

## Commands

Sub-agent loop check via `multi_agent_v1.send_input` /
`multi_agent_v1.wait_agent`.

## Inputs / Artifacts

- `history/284-stable-noninstrumented-causal-field-selection.md`
- `history/285-post-stream-idle-field-loop-check.md`
- `history/286-post-stream-idle-guest-producer-reducer.md`

## Loop-Guard Field

- `post_stream_idle_guest_producer_wait_state`

## Findings

- The sub-agent said the reducer moved the boundary: browser is not failing to
  consume or decode the post-boundary command stream; it never observes a
  post-`0x03881318` producer continuation at all.
- Native has `928` later `dma_put > 0x03881318` lines, `642` PFIFO
  continuation markers, `286` PGRAPH continuation markers, and then strict XBE
  execution.
- The next field must remain static and non-instrumented.

## Progress-Method Critique

The sub-agent said this is useful B6 progress because it moves the causal
question from PFIFO/PGRAPH consumer behavior to missing guest producer
continuation. It warned not to fall back into instrumentation to find the
missing writer.

## Decision

Continue.

## Next Step

Classify `post_boundary_guest_progress_to_dma_continuation_absence_cause` from
existing stable CPU/wait/timer evidence only.
