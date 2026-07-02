# 191. PFIFO Scheduler Source-Tag Build Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after inspecting the existing
PFIFO scheduler source-tag marker scope.

## Inputs / Artifacts

- `history/190-pfifo-scheduler-source-tag-scope-inspection.md`
- Current worktree PFIFO/PGRAPH/user/nv2a marker-only changes

## Loop-Guard Field

- `pfifo_scheduler_source_tags_build_status`

## Findings

The sub-agent decision was `continue`.

Build-only verification is the right next step. The source inspection already
established the intended marker-only scope and classifier support; the next
boundary fact is whether those existing worktree changes compile into the
browser/WASM artifact.

This stays inside the marker-only constraint because it only verifies
source-tag emission code already present in the worktree. It avoids broad PFIFO
reruns because no runtime is proposed yet and no scheduling behavior is being
changed.

## Progress-Method Critique

The method is disciplined again:

- static field selection
- static source scope check
- build-only verification before any runtime

Before any runtime, require a passing build and a single stated field:
`first_kick_after_last_opportunity_source`. Reject any runtime that also tries
to remeasure unrelated PFIFO, timer-pump, or quarantined scheduler behavior.

## Decision

Continue with Podman WASM build-only verification.

## Next Step

Run the browser/WASM build only. Do not run a browser runtime in the same step.
