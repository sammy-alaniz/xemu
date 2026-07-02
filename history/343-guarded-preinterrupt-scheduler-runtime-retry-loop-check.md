# Guarded Preinterrupt Scheduler Runtime Retry Loop Check

## Purpose

- One new fact this run was supposed to produce: whether fixture restoration
  permits exactly one guarded runtime retry.

## Command(s)

```sh
# Bounded sub-agent loop check; no shell command.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: sub-agent response for the required loop check after
  `history/342-guarded-preinterrupt-scheduler-fixture-source-inventory.md`
- Fixture assumptions: explicit `XEMU_MCPX`, `XEMU_FLASH`, `XEMU_EEPROM`, and
  `XEMU_HDD` exports from history 342 now produce
  `REAL_FIXTURE_READY_RESULT result=pass`.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `guarded_preinterrupt_scheduler_runtime_effect`.

## Findings

- Result: loop check completed.
- Important marker/comparator lines: exactly one guarded runtime retry is
  allowed now, using the explicit fixture exports from history 342.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not
  applicable; no emulator run occurred.

## Decision

- Status: current
- Why: the earlier failed attempt measured only missing fixtures, and the
  fixture-source field was changed by history 342.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: run the guarded runtime once with a fresh output
  directory and explicit fixture exports.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: retrying now is valid, not
  circular, because the failed run never measured
  `guarded_preinterrupt_scheduler_runtime_effect`. It becomes circular if there
  is another retry without a new named field or a broad return to old
  pump/vblank/PIT/PFIFO diagnostics.
- If yes, process adjustment for next 2-3 turns: run this once, immediately
  write history, then either kill/revise the guarded scheduler branch if it
  regresses preservation evidence or continue only from the new runtime field
  result.

## Next Step

- Narrow follow-up: run the single guarded browser runtime with explicit
  fixture exports and check for pre-first-read scheduler markers, first watched
  read ticks, and preservation evidence.
