# Post Early Notify Helper Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to continue from `browser_late_pgraph_notify_clear_presence` and how.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Latest static summary: `history/256-browser-late-pgraph-presence-static.md`
- Prior loop check: `history/255-exact-pgraph-query-loop-check.md`
- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Fixture assumptions: no code change or runtime occurred during this checkpoint.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain:
  - `post_early_notify_clear_native_continuation_absent_in_browser`

## Findings

- Result: continue.
- The sub-agent accepted that `browser_late_pgraph_notify_clear_presence=early-present-late-wait-state-absent` narrows the boundary.
- It recommended using the focused helper first:
  - `scripts/xbox-pgraph-command-stream-compare.py`
- It said this is not broad graphics/PFIFO rerun if limited to the existing focused helper and the exact post-early notify-clear boundary.
- Recommended next field:
  - `post_early_notify_clear_native_continuation_absent_in_browser`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; this was a loop check only.

## Decision

- Status: current
- Why: run the focused static helper if its interface fits the stable native/browser logs; otherwise use bounded exact line queries around the last shared early notify-clear and native line 6163.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the field remains tied to the missing late handoff before strict `dashboard=xbe-executed`.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the method still moves toward strict dashboard execution, visible main-menu proof, and game launch because it tracks the path native takes immediately before actual low-entry execution. It is diagnostic-heavy, but not rerun-heavy.
- If yes, process adjustment for next 2-3 turns: use the focused helper first, then only exact bounded line queries if the helper does not answer the field; no broad marker sweeps.

## Next Step

- Narrow follow-up: inspect and run `scripts/xbox-pgraph-command-stream-compare.py` against the stable native and browser logs if its usage matches.
