# 195. PFIFO Source Runtime Cancel Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after canceling the planned
PFIFO scheduler source runtime because `history/50` already answered the
selected field.

## Inputs / Artifacts

- `history/194-pfifo-source-runtime-canceled-existing-artifact.md`
- `history/50-pfifo-kick-source-runtime.md`
- Existing focused artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`

## Loop-Guard Field

- `first_nv_user_dma_put_after_opportunity_cause`

## Findings

The sub-agent decision was `continue`.

Canceling the runtime was correct. The selected field
`first_kick_after_last_opportunity_source` was already answered by `history/50`,
so rerunning would have repeated a historical diagnostic without changing the
boundary.

The next non-repeating field should be:

- `first_nv_user_dma_put_after_opportunity_cause`

Keep it static first: inspect `hw/xbox/nv2a/user.c`, the DMA_PUT marker path,
and existing logs to determine whether the late `nv-user-dma-put` is caused by
guest MMIO ordering, delayed PFIFO publication, missing earlier marker coverage,
or an already-known DMA gate. Do not rerun scheduler/pusher/window classifiers.

## Progress-Method Critique

This caught a real repeat risk. The method improved by checking history before
spending a runtime. For the next 2-3 turns, require a known-artifact check before
selecting any runtime field, and only proceed when the new field is not already
answered by existing history or scripts.

## Decision

Continue with static inspection for
`first_nv_user_dma_put_after_opportunity_cause`.

## Next Step

Inspect the DMA_PUT path and existing artifacts statically; do not run a
browser runtime or old PFIFO classifier.
