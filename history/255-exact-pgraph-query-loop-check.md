# Exact PGRAPH Query Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue after the truncated late-PGRAPH static pass.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest partial static summary: `history/254-late-pgraph-handoff-static-partial.md`
- Prior loop check: `history/253-late-handoff-progress-method-loop-check.md`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: no code change or runtime occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `browser_late_pgraph_notify_clear_presence`

## Findings

- Result: continue.
- The sub-agent said the current field is valid and not a repeat of prior negative-control work.
- It also said the previous broad search failed methodologically by producing truncated output.
- The next action must be exact static queries only.
- Recommended next field:
  - `browser_late_pgraph_notify_clear_presence`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: continue with bounded exact marker count/list queries for `pgraph-notify-clear` and `notify-error-clear`; do not start runtime, code changes, or broad graphics/PFIFO exploration.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: use exact static queries and place any browser hits relative to high-alias loop markers and absent `dashboard=xbe-executed`.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still moves toward strict dashboard execution, visible main-menu proof, and game launch because it targets the missing direct low-entry execution path immediately before `dashboard=xbe-executed`. It is becoming diagnostic-heavy, but not rerun-heavy.
- If yes, process adjustment for next 2-3 turns: use exact marker-count/list queries with bounded output, and reject broad source/log sweeps unless a focused helper already exists.

## Next Step

- Narrow follow-up: statically classify `browser_late_pgraph_notify_clear_presence` with exact bounded queries in the stable browser and native logs.
