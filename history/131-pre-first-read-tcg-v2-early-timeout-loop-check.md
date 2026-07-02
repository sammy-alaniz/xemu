# Pre First Read TCG V2 Early Timeout Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether to rerun the browser validation, change code, or first explain why
  the `v2` runtime stopped before dashboard read/load.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Required post-history B6 loop check plus critique. Read goal.md, AGENTS.md, and
history/130-pre-first-read-tcg-v2-early-timeout.md only as needed. Do not edit
files. Context: the corrected v2 runtime started emulation but timed out very
early with only 153 log lines. It had B3/browser-block and device init, but no
B4, no dashboard IDE read markers, no dashboard loaded/entry-ready, no
section-map, no PFIFO stream-idle, no memory-watch/edge/tick-block, and no
tcg=timer-pump. Therefore it did not test the changed 0x80030e84 TCG readiness
predicate. The previous v1 artifact with the older code reached dashboard
read/load/entry-ready and the B6 boundary. Proposed next action: no code tweak
and no browser rerun yet; do a no-emulation comparison of v1 vs v2 early
runtime logs plus the small source diff to determine whether the early timeout
is fixture/runtime setup drift (port/origin/EEPROM/OPFS) or a code regression,
naming a field like v2_early_timeout_cause. Answer standard loop-check
questions, include Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Runtime summary:
  `history/130-pre-first-read-tcg-v2-early-timeout.md`
- `v1` runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1/browser-runtime.log`
- `v2` runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `v2_early_timeout_cause`, `pre_first_read_tcg_checkpoint_active`, and
  `browser_first_watch_read_ticks`.

## Findings

- Result: critique decision was `revise`.
- It said another browser validation now would be looping because the corrected
  `v2` run failed far before the B6 boundary.
- It identified the narrowest next fact as `v2_early_timeout_cause`: fixture or
  runtime setup drift, browser storage/origin/OPFS state, port/session state,
  or the small TCG readiness code change.
- It killed treating `history/130` as evidence against the `0x80030e84`
  readiness predicate, because the run never reached that boundary.
- It kept the predicate validation as untested.
- It revised the immediate objective to restore the validation harness to the
  known B6 boundary before testing scheduler behavior.
- It approved a no-emulation comparison of `v1` versus `v2` early logs,
  transcripts, command/env differences, artifact paths, browser
  origin/port/OPFS usage, EEPROM path/state, and the small source diff.

## Decision

- Status: current.
- Why: the required critique rejects rerun/code-change churn until
  `v2_early_timeout_cause` is named.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: inspect logs/setup/source, not runtime, and restore
  the validation harness before testing the TCG predicate again.

## Progress-Method Critique

- The critique said the method still points toward strict dashboard execution
  because the intended target remains `browser_first_watch_read_ticks`, a
  prerequisite for `dashboard=xbe-executed`; visible main-menu proof and game
  launch remain downstream.
- It said the work risks becoming rerun-heavy if runtime validation continues
  before explaining why the harness no longer reaches dashboard read/load.
- It said the history/loop-check process is helping by separating setup failure
  from B6 evidence.
- It said code/log inspection is the right next mode, not code change or
  runtime probing.
- Process adjustment: before any next runtime, require a short preflight
  comparison showing the run can plausibly reach the `v1` B6 boundary, or name
  the specific setup variable being restored.

## Next Step

- Narrow follow-up: perform a no-emulation comparison to identify
  `v2_early_timeout_cause` before any further browser run or code change.
