# Pre-First-Read Micro-Scheduler Activation Loop Check

## Purpose

- One new fact this loop check was supposed to produce: decide whether to revise the before-interrupt pump-site activation after the first runtime regressed before entry-ready.

## Command(s)

```sh
# Bounded sub-agent loop check against history/148.
# Agent: 019f1e51-23ca-7e93-978c-89e48eb1dc60
```

## Inputs And Artifacts

- Runtime log:
  `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-v1/browser-runtime.log`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: runtime reached only B3/browser harness evidence, not the B6 boundary.

## Expected Field(s)

- Loop-guard field(s) this loop check could change or explain: `scheduler_site_armed_only`

## Findings

- Result: continue.
- Are we looping? Not if runtime probing stops and activation scope is fixed.
- Narrowest next fact: whether the before-interrupt pump site can be inactive until the pre-first-read scheduler is actually eligible to arm, preserving normal same-origin behavior before entry-ready.
- Kill: enabling the before-interrupt pump site for the whole new mode from process start.
- Keep: the micro-scheduler concept remains viable but unmeasured because it never reached its activation boundary.
- Revise: split mode selection from site activation. The before-interrupt site should require entry-ready and scheduler-specific readiness before changing CPU loop behavior.
- Code revision is justified because the runtime failed to measure `pre_first_read_tick_block_completions_browser` and regressed before B4/dashboard read.

## Decision

- Status: current
- Why: one narrow code slice can change `scheduler_site_armed_only` without adding another runtime variable.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: no runtime should run until site activation is revised, the build passes, and a post-history loop check approves validation.

## Progress-Method Critique

- This still connects to strict browser B6 because the scheduler targets the pre-first-read tick gap blocking real dashboard execution.
- The work risks diagnostic churn, but the last runtime gave a clear implementation failure before the intended boundary.
- The history/loop-check process is helping by preventing another invalid runtime.
- Right next mode: code change.
- Process adjustment: revise only site activation, build, then loop-check before validation. Treat restored B4/read/load/entry-ready as a prerequisite before judging scheduler stop reasons.

## Next Step

- Narrow follow-up: add an armed-only before-interrupt site predicate, preserving existing same-origin behavior before entry-ready.
