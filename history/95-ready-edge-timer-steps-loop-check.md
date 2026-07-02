# Ready Edge Timer Steps Loop Check

## Purpose

- One new fact this checkpoint was supposed to produce: whether to patch the ready-edge host pump so it can honor the existing timer-step setting without enabling full deterministic mode.

## Command(s)

```text
Spawned read-only sub-agent 019f1e11-de9b-7b61-989b-815d14db3585 with this checkpoint:

Read goal.md, history/93, and history/94. Decide whether to patch
ui/xemu-headless.c so non-deterministic ready-edge host pumping honors
XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS.
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Latest runtime log: `build-real-b3-matrix/browser-main-menu-edge-decision-last-pfifo-idle-v1/browser-runtime.log`
- Fixture assumptions: read-only critique; no runtime state changes.

## Expected Field(s)

- Loop-guard field(s) this checkpoint could change or explain: whether the next code change is justified for `browser_first_watch_read_ticks`.

## Findings

- Result: critique decision was `continue`.
- The checkpoint said this is not looping if the next action is the narrow timer-step plumbing change.
- It said the narrowest next fact is whether non-deterministic ready-edge host pumping with `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS=2` moves `browser_first_watch_read_ticks` from `0` to `>0`.
- It killed further edge-decision schema work as useful for this boundary.
- It kept the hypothesis that browser reaches the first watched read too early relative to virtual timer accumulation.
- It revised full deterministic mode as not the next lever because it previously blocked before `entry_ready`.

## Decision

- Status: current
- Why: the proposed change names exactly one primary field, uses an existing mechanism, and does not weaken the success contract.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: patch ready-edge host pump to reuse the timer-step count with deterministic mode off, then run one steps=2 experiment.

## Progress-Method Critique

- No edge-decision schema work.
- Reusing `XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS` is acceptable for the immediate diagnostic because it already describes timer steps and is already forwarded by browser runtime plumbing.
- If this becomes promoted behavior, rename or alias it to a clearer name such as `XEMU_BROWSER_BOOT_TIMER_PUMP_STEPS`.
- The run log must make clear deterministic mode is off and only the step count is honored.

## Next Step

- Narrow follow-up: patch `ui/xemu-headless.c` so the ready-edge host pump uses the existing step count even when `XEMU_BROWSER_BOOT_DETERMINISTIC=1` is not set.
