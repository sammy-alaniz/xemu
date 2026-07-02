# Edge Decision Trace Loop Check

## Purpose

- One new fact this run was supposed to produce: whether the proposed
  `0x80030e84` edge-decision trace is justified after history/72, and what it
  must capture to avoid another loop.

## Command(s)

```sh
# Spawned bounded sub-agent critique after history/72.
```

## Inputs And Artifacts

- Baseline native log: none.
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Additional browser log:
  `build-real-b3-matrix/browser-main-menu-deterministic-m1-v1-combined.log`
- Output directory/log: sub-agent response only.
- Fixture assumptions: no emulation run.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `browser_post_service_top_edge`.

## Findings

- Result: critique decision was `revise`.
- Important marker/comparator lines:
  - The next fact should identify which pre-branch input differs for the
    `0x80030e84` block: GPRs, eflags, `0x80035c34`, or another memory operand.
  - The trace must not only log the first `0x80030e84` hit, because the baseline
    useful same-tick comparison occurs at the later `0x00007530` hit.
  - Register snapshots must be pre-TB; post-TB state is not the branch input.
  - Avoid raw code hex in committed artifacts; hashes and decoded operands are
    enough unless local disassembly is needed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was a critique checkpoint only.

## Decision

- Status: current
- Why: the next code change is justified only if it adds a bounded, opt-in,
  pre-TB edge-decision trace for a few post-idle `0x80030e84` hits.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: do not patch deterministic scheduling yet; first
  collect branch input state for `browser_post_service_top_edge`.

## Next Step

- Narrow follow-up: add the opt-in pre-TB `edge-decision` marker around
  `cpu_loop_exec_tb` for bounded post-idle `pc==0x80030e84` hits, logging GPRs,
  eflags, watched word, `0x80035c34`, wait/IRQ state, and code hash/opcode
  metadata.
