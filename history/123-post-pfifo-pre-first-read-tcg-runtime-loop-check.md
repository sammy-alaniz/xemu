# Post PFIFO Pre First Read TCG Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether the negative runtime in `history/122` justifies another browser run,
  a gate revision, or stopping this TCG checkpoint path.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Required post-history B6 loop check. Read goal.md, AGENTS.md, and
history/122-post-pfifo-pre-first-read-tcg-runtime.md only as needed. Do not
edit files. Context: the browser runtime validation applied
XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read, but no
BOOT_MARK b6 tcg=timer-pump marker appeared; strict B6 still failed at
missing-xbe-executed-marker; browser_first_watch_read_ticks stayed 0 vs native
136; section-map/read/load/entry-ready stayed good; the post-service top edge
regressed from baseline 0x80030e84->0x80030f31 to 0x80018e04->0x80018e07.
Answer the standard loop-check questions, include the required
Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Runtime summary:
  `history/122-post-pfifo-pre-first-read-tcg-runtime.md`
- Combined runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v1-combined.log`
- Fixture assumptions: read-only critique; no runtime or code changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_tcg_gate_blocker`, `pre_first_read_tcg_checkpoint_active`,
  `browser_first_watch_read_ticks`, and `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `revise`.
- It said we are not looping yet, but another runtime with the same
  `pit-post-pfifo-pre-first-read` gate would be looping.
- It said the one approved runtime answered its field:
  `pre_first_read_tcg_checkpoint_active=no`.
- It identified the narrowest next fact as `pre_first_read_tcg_gate_blocker`,
  the exact readiness predicate that stayed false before the first watched
  read.
- Likely blocker candidates named by the critique: serviceable idle PC
  requirement, pending IRQ state, IRQ inhibition, expired PIT timer detection,
  PFIFO-empty wait state, or the edge/tick-block stop guards.
- It killed the hypothesis that the new mode is runtime-ready as-is.
- It kept TCG-loop ownership as more defensible than browser host polling,
  because it avoids browser cadence and manual interrupt mutation.
- It revised the hypothesis to: the gate is probably too narrow or keyed to the
  wrong CPU context. The runtime hit `0x80018e04` with pending IRQ and
  `0x80014f32` with IRQ inhibited, not the clean serviceable idle-loop state
  required by the mode.
- It said a second runtime is not justified.
- It recommended static/log inspection of the readiness helper against the
  `history/122` combined timeline to classify each gate predicate before the
  first watched read and identify the first blocker.

## Decision

- Status: current.
- Why: the loop check rejects another browser runtime until the closed TCG gate
  is explained from source/log evidence.
- Independent critique used: yes.
- If yes, critique decision: revise.
- If yes, critique summary: inspect or instrument the readiness predicate, but
  do not rerun the same mode until `pre_first_read_tcg_gate_blocker` is known.

## Progress-Method Critique

- The critique said the method still connects to strict dashboard execution
  because `browser_first_watch_read_ticks` remains the field blocking
  browser-runtime `dashboard=xbe-executed`, with visible main-menu proof and
  game launch downstream.
- It said the work is becoming diagnostic-heavy, but the loop checks are
  helping by preventing immediate reruns after a closed gate.
- It recommended code/log inspection rather than runtime probing for the next
  2-3 turns.
- Process adjustment: every scheduler change must name the readiness predicate
  it changes and keep post-service edge preservation as a hard guard.

## Next Step

- Narrow follow-up: perform a no-emulation source/log gate audit to identify
  `pre_first_read_tcg_gate_blocker` before any further browser runtime or TCG
  checkpoint revision.
