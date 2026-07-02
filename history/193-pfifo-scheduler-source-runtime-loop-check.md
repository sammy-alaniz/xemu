# 193. PFIFO Scheduler Source Runtime Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after the PFIFO scheduler
source-tag build passed, before any runtime.

## Inputs / Artifacts

- `history/192-pfifo-scheduler-source-tag-build-pass.md`
- Rebuilt `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Field

- `first_kick_after_last_opportunity_source`

## Findings

The sub-agent decision was `continue`.

One runtime is justified because the marker scope is fixed, the build is
verified, and no runtime has tested
`first_kick_after_last_opportunity_source` yet.

The validation set is scoped enough if treated as guard plus one classifier:

- combine dashboard read evidence
- strict B6 helper
- B4 display helper
- section-map helper
- PFIFO scheduler classifier
- current boundary helper for preservation

Do not add separate old PFIFO-window, pusher-entry, timer-opportunity, or
scheduler reruns beyond what the existing boundary script already reports.

## Progress-Method Critique

This runtime has a single new field and remains tied to strict B6: it asks where
the first PFIFO kick after the missed timer-opportunity window comes from, while
preserving the stable CPU-flow baseline.

If the run does not preserve B4/B5/read/load/entry-ready/section-map and the
post-service comparator path, do not interpret the new source tag as causal;
first classify it as a baseline regression.

## Decision

Continue with exactly one focused browser runtime.

## Next Step

Run the focused browser runtime with the stable ready-edge host4 diagnostic
shape and `XEMU_BOOT_TRACE_NV2A_PFIFO_SCHEDULER_LIMIT=128`, then run only the
approved guard/classifier helpers.
