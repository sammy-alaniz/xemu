# Edge Decision Runtime Rerun Loop Check

## Purpose

- One new fact this run was supposed to produce: whether the failed sandbox run
  from history/76 justifies rerunning the same focused browser experiment with
  escalated permissions.

## Command(s)

```sh
# Spawned bounded sub-agent critique after history/76.
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Failed run log:
  `build-real-b3-matrix/browser-main-menu-edge-decision-det-v1/browser-runtime.log`
- Output directory/log: sub-agent response only.
- Fixture assumptions: no successful emulation run.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `continue`.
- Important marker/comparator lines:
  - History/76 failed before browser runtime started due to sandbox socket
    permissions.
  - That failure says nothing about B6 timing, PFIFO, IRQ, or dashboard
    execution.
  - Escalation changes only the environment permission needed to let the exact
    intended experiment start.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a critique checkpoint only.

## Decision

- Status: current
- Why: rerunning the same focused command with escalation is justified and still
  targets only `browser_post_service_top_edge`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: no better prerequisite experiment exists before the
  escalated rerun.

## Next Step

- Narrow follow-up: rerun the focused browser runtime with
  `XEMU_BOOT_TRACE_XBE_EDGE_DECISION_LIMIT=4` under escalated permissions.
