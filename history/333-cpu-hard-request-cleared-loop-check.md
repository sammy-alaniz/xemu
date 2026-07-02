# 333. CPU Hard Request Cleared Loop Check

## Purpose

Run the required bounded sub-agent loop check after
`history/332-cpu-hard-request-cleared-without-service-static.md`, including
progress-method critique.

## Exact Commands

No shell command. Spawned a bounded read-only sub-agent checkpoint.

## Inputs / Artifacts

- `history/332-cpu-hard-request-cleared-without-service-static.md`
- Current B6/main-menu goal and loop-control rules from `goal.md` /
  `AGENTS.md`
- Browser runtime artifact:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pcrtc-final-window-bql-v1/browser-runtime.log`

## Loop-Guard Field

`first_watch_read_tick_gap_owner`

## Findings

The sub-agent judged the CPU hard-request finding useful, but recommended
revising the active path. PCRTC final-window forcing proved BQL ownership and
NV2A IRQ assertion are not the blocker, and proved the interrupt can reach
`CPU_INTERRUPT_HARD`. However, because that path does not become a vector
service and the guest handles it by PMC polling, more PCRTC forcing is likely
non-causal unless native proves the same PCRTC/PIRQ path is required before the
first watched poll.

The sub-agent recommended the next action be a static helper over existing
native/browser logs, not another runtime. The helper should classify what
differs before the first `0x0003a890` watched read: last tick write, last timer
dispatch, hard-IRQ service/ack/IRET, PIC state, and PMC/PCRTC/PIT state.

## Decision

Revise.

## Next Step

Create a focused static comparator for `first_watch_read_tick_gap_owner` using
the existing native and browser artifacts. Do not run another PCRTC
final-window, pump/vblank, PIT, precommit, or timing variant unless that new
field specifically requires one.

## Loop-check progress-method critique included

Yes.

## Progress-method critique summary

The sub-agent said the method has converged so far, but the interrupt boundary
is now close to over-instrumented. It recommended continuing static
native-vs-browser comparisons around first watched read and tick production,
and stopping pump, vblank, PIT, precommit, and final-window runtime variants
unless the new field requires one. The causal metric remains valid only if it
explains pre-service tick accumulation and leads back to strict XBE execution.
