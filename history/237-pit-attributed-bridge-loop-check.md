# PIT Attributed Bridge Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: decide whether `history/236-pre-stream-timer-irq-gate-replacement-viability.md` justifies code work, more static design, or stopping.

## Command(s)

```sh
# Sub-agent loop check via multi_agent_v1 on existing agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest static summary: `history/236-pre-stream-timer-irq-gate-replacement-viability.md`
- Output directory/log: sub-agent response only
- Fixture assumptions: no runtime or file edits by the sub-agent.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether a PIT-attributed bridge patch is approved, and the single next field it may change.

## Findings

- Result: continue.
- The sub-agent agreed that `pre_stream_timer_irq_gate_replacement_viability` is non-redundant because it distinguishes the missing native-like pre-stream vector service from old "pump more" attempts.
- The sub-agent said the PIT-attributed bridge is materially different only if it remains opt-in and PIT-only:
  - run `QEMU_TIMER_ATTR_XEMU_TCG_PUMP` timers only,
  - never run all timers,
  - do not touch PCRTC/vblank, NV2A, precommit, warmup-count tuning, or scheduler hooks,
  - leave strict B6 unchanged.
- The approved next action is one small code patch plus build-only verification.
- Exactly one next field: `pit_attributed_pre_stream_bridge_build_status`.
- No runtime is approved until after the patch/build history entry and another loop check.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: one opt-in PIT-only bridge patch is allowed, but only to reach build status. Runtime behavior must wait for a new loop check.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the path is causal if it stays a narrow replacement for the PFIFO-empty timer IRQ gate. The method risk is relabeling another host-pump experiment as architecture. The constraint is source-tagged, tiny bounded, opt-in PIT-only delivery with documented preservation gates and a branch-exit rule for any later B4/B5/read/load/entry-ready/section-map/stream-idle/vector `0x30`/IRET/post-service-edge regression.

## Next Step

- Narrow follow-up: patch the smallest opt-in PIT-only pre-stream bridge and run build-only verification for `pit_attributed_pre_stream_bridge_build_status`; do not run browser runtime yet.
