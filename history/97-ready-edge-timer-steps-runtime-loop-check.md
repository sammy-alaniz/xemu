# Ready Edge Timer Steps Runtime Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to run the first browser runtime using ready-edge host timer steps with deterministic mode off.

## Command(s)

```text
Spawned read-only sub-agent 019f1e13-f1b7-7213-96c1-5501b4118c5d with this checkpoint:

Read goal.md, history/95, and history/96. Decide whether to run one ready-edge
host4 browser runtime with XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2 and
full deterministic mode unset/off.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest build artifact: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether one runtime is justified to test `browser_first_watch_read_ticks`.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said this is not looping because the patched behavior has not yet been tested at runtime.
- The narrowest next fact is whether `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2`, with full deterministic mode off, moves `browser_first_watch_read_ticks` from `0` to `>0` while preserving gates.
- It killed more edge-decision/schema work as the next move.
- It kept the hypothesis that browser reaches the first watched read before enough timer accumulation.
- It revised compile success as insufficient; the timer-step plumbing matters only if it advances the watched word before the first read.

## Decision

- Status: current
- Why: one steps=2 runtime directly exercises the patched path and names one primary field.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: run one steps=2 ready-edge host4 runtime, then stop if the field does not move instead of increasing step count blindly.

## Progress-Method Critique

- Keep the method centered on `browser_first_watch_read_ticks`, not repeated B6 failure.
- If steps=2 moves the field above `0` and gates hold, continue with the smallest next step or focused ordering check to see whether movement scales.
- If steps=2 does not move it, stop increasing step count blindly; the hypothesis shifts to ordering-after-first-read or wrong producer.
- If steps=2 regresses gates, classify it as perturbing evidence, not a baseline.

## Next Step

- Narrow follow-up: run exactly one ready-edge host4 browser runtime with `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2`, deterministic mode unset/off, and reduce `browser_first_watch_read_ticks`.
