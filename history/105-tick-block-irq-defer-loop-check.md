# Tick Block IRQ Defer Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether the failed
  IRQ-defer runtime in `history/104` justifies a bounded code revision, another
  runtime, or stopping.

## Command(s)

```text
Spawned read-only sub-agent 019f1e3f-e019-72a3-991c-3faac8c8c83d
with this checkpoint:

Read goal.md, AGENTS.md, history/103-tick-block-completion-loop-check.md, and
history/104-tick-block-irq-defer-runtime.md. Evaluate the latest tick-block IRQ
defer runtime, including the stale sampled interrupt argument versus captured
CPU context mismatch. Answer the standard loop-check questions and include the
required Progress-Method Critique. End with continue, revise, or stop.
```

## Inputs And Artifacts

- Latest runtime log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1/browser-runtime.log`
- Latest combined log:
  `build-real-b3-matrix/browser-tick-block-irq-defer-readyedge-host4-v1-combined.log`
- Latest run summary: `history/104-tick-block-irq-defer-runtime.md`
- Fixture assumptions: read-only critique; no code or runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `irq_defer_engaged`, `pre_first_read_tick_block_completions_browser`,
  `browser_first_watch_read_ticks`, and post-service edge preservation.

## Findings

- Result: critique decision was `continue`.
- The checkpoint verified the runtime facts from `history/104`: the mode was
  applied, `tick-block-irq-defer` skipped with `reason=no-hard-irq`, the same
  marker captured `ctx_interrupt_request=0x00000002` and
  `ctx_exit_request=yes`, no `tick-block=complete` appeared,
  `browser_first_watch_read_ticks` stayed `0`, and post-service edge
  preservation regressed to `block-start-branch-mismatch`.
- It said this is not looping yet because the run explained why the behavioral
  change did not engage.
- It killed the hypothesis that the sampled pre-call interrupt/exit arguments
  are reliable enough for this decision.
- It kept the hypothesis that browser reaches the watched read too early
  relative to pending PIT/PIC/CPU interrupt handling.
- It revised the one-TB defer hypothesis: the implementation failed, not the
  underlying idea.

## Decision

- Status: current.
- Why: the next action should be a small code revision that uses the effective
  captured CPU state for the defer decision.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: patch the defer decision to compute and log
  `effective_interrupt_request`, `effective_exit_request`, and
  `sample_mismatch`, then run exactly one validation.

## Progress-Method Critique

- The critique said the metrics still connect to the real goal because strict
  browser `dashboard=xbe-executed` remains the prerequisite for main-menu
  capture, input, and game launch.
- It said the broader effort is diagnostic-heavy, but this artifact produced a
  concrete implementation fault rather than merely reconfirming failure.
- It said the history/loop-check process is helping over the next 2-3 turns by
  forcing one named-field change at a time.
- It recommended a small code inspection plus code change, followed by one
  runtime validation.
- Process adjustment for the next 2-3 turns: do not add new fields beyond the
  effective-state mismatch and the four validation fields.

## Next Step

- Narrow follow-up: change the tick-block IRQ defer pre-hook to use captured CPU
  context as the effective interrupt/exit state when it differs from the
  pre-call sampled arguments, then build and run one validation only.
