# Pre-First-Read Post-STI Pump Runtime Loop Check

## Purpose

- One new fact this run was supposed to produce: whether the exact post-STI first-read predecessor timer-pump build justifies one browser runtime validation.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest build history `history/164-pre-first-read-post-sti-pump-build-pass.md`
- exact `0x80014f32` predicate change
- proposed field `post_sti_first_read_predecessor_timer_pump`
- runtime success criteria
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Built target: `build-wasm-pic/qemu-system-i386.js`
- Prior history entry: `history/164-pre-first-read-post-sti-pump-build-pass.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_first_read_predecessor_timer_pump`.

## Findings

- Result: one runtime validation is justified.
- Are we looping? No; this validates the audited exact `0x80014f32` condition.
- Narrowest next fact: `post_sti_first_read_predecessor_timer_pump`, meaning whether the scheduler starts at or near `0x80014f32` and produces a `tcg=timer-pump` before the watched-word read.
- Kill: broad IRQ-inhibited serviceability and any `0x80014f3d` expansion.
- Keep: strict B6 must remain real; read/load/entry-ready/section-map/PFIFO/post-service edge are guards, not substitutes for `dashboard=xbe-executed`.
- Revise: the scheduler hypothesis is now narrowly post-STI first-read predecessor timer pumping.
- One runtime justified now? Yes.
- Better experiment? None before this validation.
- Progress-method critique: the metrics remain connected to strict dashboard execution because the first-read tick gap blocks real browser `dashboard=xbe-executed`; visible main menu and game launch remain downstream. The work is diagnostic-heavy, but this step validates a concrete audited predicate. The next mode should be runtime probing with no code changes.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: judge the runtime first on `scheduler=pre-first-read phase=start` at/near `0x80014f32`, then `tcg=timer-pump`, `browser_first_watch_read_ticks`, preservation gates, and strict B6.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: continue with one runtime validation; no more code changes before measuring the exact scheduler-start field.

## Next Step

- Narrow follow-up: run one browser runtime with `pit-pre-first-read-micro-scheduler`. Primary field: `post_sti_first_read_predecessor_timer_pump`.
