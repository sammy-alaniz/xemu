# Pre First Read TCG Gate Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether the gate audit in `history/124` justifies a narrow code revision or
  whether more inspection/runtime probing is needed first.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Required post-history B6 loop check. Read goal.md, AGENTS.md, and
history/124-pre-first-read-tcg-gate-audit.md only as needed. Do not edit files.
Context: the no-emulation audit identified
pre_first_read_tcg_gate_blocker=idle-loop-pc-only-gate. The failed
pit-post-pfifo-pre-first-read mode never emitted BOOT_MARK b6 tcg=timer-pump
because its readiness helper only accepts pc == 0x8001b030. The useful
pre-read checkpoint in the browser artifact is after 0x80014f32->0x80030e84:
PFIFO empty, no pending interrupt, no IRQ inhibition, no tick-block complete,
no edge-decision, watched value still 0, next instruction reads physical
0x0003a890. Earlier checkpoints are blocked by pending IRQ, IF clear, or IRQ
inhibited. Native also reaches the watched read through a 0x80030e84
pre-read/tick-block boundary, with the watched value already nonzero. Proposed
next action: a small code revision only inside the pit-post-pfifo-pre-first-read
readiness path to permit a bounded TCG PIT pump at pc == 0x80030e84 under the
existing PFIFO-empty/no-edge/no-tick/no-pending/no-inhibit/expired-timer
conditions, without manual interrupt mutation and without weakening strict B6.
Answer the standard loop-check questions, include the required
Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Audit summary:
  `history/124-pre-first-read-tcg-gate-audit.md`
- Runtime artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log`
- Fixture assumptions: read-only critique; no runtime or code changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_tcg_checkpoint_pc_allowed`,
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping if the next step is the proposed narrow code
  revision. Another runtime without changing the predicate would be looping.
- It identified the narrowest next fact as whether permitting
  `pc == 0x80030e84` inside `pit-post-pfifo-pre-first-read` readiness lets the
  checkpoint activate at the useful pre-read/tick-block boundary under the
  existing safety guards.
- It killed the idle-loop-only PC gate for this mode.
- It kept TCG-owned PIT delivery plus normal CPU interrupt handling as the
  right architecture and kept exact-PC IRQ defer dead.
- It revised the mode hypothesis to allow the tick-block pre-read PC
  `0x80030e84`, not only idle-loop `0x8001b030`.
- It said no better experiment is needed before the code change.
- It said the code revision changes
  `pre_first_read_tcg_checkpoint_pc_allowed`; a later runtime can test
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  post-service edge preservation.

## Decision

- Status: current.
- Why: the required critique approved exactly one scoped code revision, with no
  runtime probing before build/static verification.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: change only the `pc == 0x80030e84` predicate for
  this TCG mode, keep all existing safety gates, then build and stop for the
  required post-history check before browser validation.

## Progress-Method Critique

- The critique said the method still moves toward strict dashboard execution
  because it targets the exact tick/CPU ordering gap blocking browser-runtime
  `dashboard=xbe-executed`; visible main-menu proof and game launch remain
  downstream.
- It said the work is diagnostic-heavy, but the last audit was productive
  rather than rerun-heavy because it found one concrete gate blocker.
- It said the history/loop-check process is helping for the next 2-3 turns by
  preventing another blind runtime.
- It said the right next mode is code change, not runtime probing or more broad
  inspection.
- Process adjustment: change only the `pc == 0x80030e84` predicate in this TCG
  mode, keep all existing safety gates, then build and stop for the required
  post-history check before browser validation.

## Next Step

- Narrow follow-up: revise `pit-post-pfifo-pre-first-read` readiness so the
  bounded TCG PIT pump can fire at `0x80030e84` under the existing PFIFO-empty,
  no-edge, no-tick, no-pending, no-inhibit, and expired-timer guards.
