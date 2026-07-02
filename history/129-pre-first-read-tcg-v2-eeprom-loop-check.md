# Pre First Read TCG V2 EEPROM Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce:
  whether the EEPROM preflight failure in `history/128` consumed the approved
  browser validation or whether one corrected rerun is justified.

## Command(s)

```text
Reused read-only sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60 with this checkpoint:

Required post-history B6 loop check. Read goal.md, AGENTS.md, and
history/128-pre-first-read-tcg-v2-eeprom-preflight-fail.md only as needed. Do
not edit files. Context: the approved v2 browser validation did not start
emulation. The log is only four lines and failed fixture preflight because
XEMU_EEPROM=/tmp/xemu-b6-eeprom-v2.bin did not exist. No B4/B5/section-map/TCG
/B6 evidence was produced. Proposed next action: rerun the exact approved
validation shape once, but with the known existing prior EEPROM path
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin, keeping the same v2 output artifact or
replacing the failed 4-line preflight log. Answer standard loop-check
questions, include Progress-Method Critique, and end with one decision.
```

## Inputs And Artifacts

- Failed preflight summary:
  `history/128-pre-first-read-tcg-v2-eeprom-preflight-fail.md`
- Failed runtime log:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2/browser-runtime.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  `pre_first_read_tcg_checkpoint_active`, `browser_first_watch_read_ticks`, and
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- It said we are not looping because the attempted `v2` did not start
  emulation, so it did not consume the approved runtime validation.
- It identified the narrowest next fact as whether the revised mode emits
  `tcg=timer-pump` at `eip=0x80030e84` and changes
  `pre_first_read_tcg_checkpoint_active`.
- It killed using a fresh `/tmp/xemu-b6-eeprom-v2.bin` path without creating
  it.
- It kept the approved validation hypothesis as untested.
- It revised only fixture setup: use the known existing
  `/tmp/xemu-b6-eeprom.bin`.
- It said exactly one rerun of the same approved validation shape is justified.

## Decision

- Status: current.
- Why: the failure was fixture preflight only; rerunning with the known-good
  EEPROM path tests the already-approved field without changing the experiment.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: replace only the EEPROM path, keep the `v2`
  artifact acceptable, and judge the run by checkpoint marker, tick movement,
  and post-service edge preservation.

## Progress-Method Critique

- The critique said this still moves toward strict dashboard execution because
  the intended runtime targets the pre-first-read tick gap blocking
  `dashboard=xbe-executed`; visible main-menu proof and game launch remain
  downstream.
- It said this is not rerun-heavy because the previous attempt failed before
  emulation and produced no evidence.
- It said the history/loop-check process helped prevent a fixture mistake from
  being counted as negative B6 evidence.
- It said runtime probing is still the right next mode.
- Process adjustment: reuse known-good fixture paths for controlled reruns
  unless a new artifact explicitly requires isolated fixture generation.

## Next Step

- Narrow follow-up: rerun the approved `v2` browser validation with
  `XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin` and no other experiment-shape changes.
