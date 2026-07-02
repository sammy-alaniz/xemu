# Late PGRAPH Handoff Static Partial

## Purpose

- One new fact this run was supposed to produce: `browser_missing_late_pgraph_notify_clear_handoff_state`.

## Command(s)

```sh
rg -n "pgraph-notify-clear|notify-error-clear|nv2a_wait_source|nv2a_wait_op|dashboard=xbe-executed|dashboard=xbe-exec-transition|dashboard=xbe-dispatch-probe|dashboard=xbe-entry-target-probe|dashboard=kernel-loop-probe|pfifo=stream-idle" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n "pgraph-notify-clear|notify-error-clear|nv2a_wait_source|nv2a_wait_op|dashboard=xbe-executed|dashboard=xbe-exec-transition|dashboard=xbe-dispatch-probe|dashboard=xbe-entry-target-probe|dashboard=kernel-loop-probe|pfifo=stream-idle" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "nv2a_wait_source|nv2a_wait_op|pgraph-notify-clear|notify-error-clear|xbe-exec-transition|xbe-dispatch-probe|kernel-loop-probe" \
  xemu-xbe.c hw ui include scripts browser | head -n 200
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: existing logs only.
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `browser_missing_late_pgraph_notify_clear_handoff_state`

## Findings

- Result: partial; the command was too broad and the output was truncated.
- Native late handoff region is visible and useful:
  - line 6163: `dashboard=kernel-loop-probe ... start_pc=0x8001e374 next_pc=0x8001e374 ... nv2a_wait_source=pgraph-notify-clear nv2a_wait_op=notify-error-clear`
  - line 6176: `dashboard=xbe-dispatch-probe ... guest_pc=0x8001e374`
  - line 6178: `dashboard=xbe-executed ... guest_pc=0x00017d60 ... image_pc=0x00017d60 ... address_mode=direct ... phys_match=yes`
- The visible browser evidence shows early `pgraph/intr-enable` states and later timeout-style high-alias loops at `0x8001b02f/0x8001b030`, with no visible direct low-entry execution.
- The broad source search confirms the relevant wait-state fields are emitted by existing marker paths in `xemu-xbe.c`, and `pgraph-notify-clear` originates in `hw/xbox/nv2a/pgraph/pgraph.c`.
- The run does not yet prove whether the stable browser log has zero `pgraph-notify-clear` / `notify-error-clear` markers or has them hidden in the truncated output.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: failed run
- Why: this was the correct static field, but the grep pattern was too broad to close it. The next step should be a bounded exact static query, not a runtime run.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/253-late-handoff-progress-method-loop-check.md` requested this static field.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the method is still aligned, but warned not to turn PGRAPH into broad graphics/PFIFO exploration.
- If yes, process adjustment for next 2-3 turns: use exact marker-count queries or an existing focused helper; avoid broad `rg` patterns that flood output.

## Next Step

- Narrow follow-up: run the required post-history loop check, then use bounded exact static queries for `pgraph-notify-clear` / `notify-error-clear` in the stable browser and native logs.
