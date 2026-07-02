# Pre-First-Read Gate Marker Filter Loop Check

## Purpose

- One new fact this run was supposed to produce: whether to revise the gate marker after `history/156`, rerun as-is, or stop the scheduler-gate branch.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest negative runtime history `history/156-pre-first-read-gate-marker-runtime.md`
- current finding that all 64 gate markers were consumed before entry-ready
- proposed next field `entry_ready_gate_scheduler_not_armed_reason`
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-pre-first-read-gate-marker-v1/browser-runtime.log`
- Prior history entry: `history/156-pre-first-read-gate-marker-runtime.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `entry_ready_gate_scheduler_not_armed_reason`.

## Findings

- Result: sub-agent recommends a narrow code revision before any runtime rerun.
- Are we looping? Not if we fix the marker filter before rerunning. Rerunning the same gate-marker build would loop.
- Narrowest next fact: `entry_ready_gate_scheduler_not_armed_reason`, the first scheduler gate state after `entry_ready=yes` and before the watched read consumes zero.
- Kill: emitting `scheduler=pre-first-read-gate` as soon as `loaded=yes`.
- Keep: the scheduler-not-armed question remains valid.
- Revise: gate-marker emission should require `entry_ready=yes` and avoid watched-word reads before entry-ready, while keeping scheduler behavior unchanged.
- Code revision justified now? Yes.
- Better experiment? No better runtime experiment yet; the better step is the narrow diagnostic filter change.
- Progress-method critique: the metrics remain connected to strict B6 because the unresolved scheduler gate blocks `browser_first_watch_read_ticks`, which blocks real `dashboard=xbe-executed`; main menu and game launch remain downstream. The work is diagnostic-heavy but narrowly correcting a concrete diagnostic failure. The next mode should be code change, then build, then a separate loop check before runtime.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: the next code change can change the field from already-known `entry-not-ready` spam to the intended entry-ready close-window gate reason.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: continue only with an entry-ready-only gate marker and no scheduler behavior change. Every bounded diagnostic budget should start no earlier than the phase it is meant to explain.

## Next Step

- Narrow follow-up: patch `scheduler=pre-first-read-gate` emission to require `entry_ready=yes` before consuming budget or reading the watched word.
