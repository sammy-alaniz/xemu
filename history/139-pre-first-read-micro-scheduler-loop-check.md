# Pre-First-Read Micro-Scheduler Loop Check

## Purpose

- One new fact this loop check was supposed to produce: decide whether the next step should be a code change that owns bounded pre-first-read tick accumulation in the emulation-thread path.

## Command(s)

```sh
# Bounded sub-agent loop check against history/138.
# Agent: 019f1e51-23ca-7e93-978c-89e48eb1dc60
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Supporting browser log: `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log`
- Output directory/log: sub-agent final response only
- Fixture assumptions: strict browser-runtime `dashboard=xbe-executed` remains required; current same-origin browser harness remains valid.

## Expected Field(s)

- Loop-guard field(s) this loop check could change or explain: `pre_first_read_tick_block_completions_browser`, `browser_first_watch_read_ticks`, post-service edge preservation

## Findings

- Result: continue.
- Are we looping? Not if we stop the current after-TB TCG pump predicate path. We would loop by continuing pump predicate tuning after `tcg_pump_after_first_read_reason=after-tb-observation-order-and-nonproducer`.
- Narrowest next fact: whether an opt-in emulation-thread checkpoint can produce at least one normal guest tick-block completion before the first watched read consumes zero.
- Kill: after-TB PIT pump predicate tuning as the producer of native-like pre-read tick accumulation.
- Keep: strict `dashboard=xbe-executed` and normal QEMU timer/interrupt paths.
- Revise: scheduler hypothesis becomes bounded emulation-thread guest progress before first watched read, not one timer delivered at a better pump point.
- Proposed code slice is justified if narrow and opt-in, because it names fields that can change and has explicit stop reasons.
- Better code shape: smallest micro-scheduler helper in the TCG/emulation-thread path that runs normal timers, allows normal `cpu_handle_interrupt()`, executes bounded normal TBs, and stops on `tick-block-before-first-read`, `first-read-before-tick-block`, `tb-budget`, or `edge-regressed`.

## Decision

- Status: current
- Why: this changes the primary field directly instead of repeating timer placement diagnostics.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: the method still connects to strict dashboard execution because the watched-word tick gap is the active blocker before visible main-menu proof and game launch. The history/loop-check process is helping by requiring the next step to name a measurable field and stop condition. The next mode should be code change, followed by build, history, and another loop check before runtime validation.

## Progress-Method Critique

- Current metrics still connect to strict dashboard execution, visible main-menu proof, and game launch because closing the pre-first-read tick gap is the active B6 blocker.
- The work has been diagnostic-heavy, but the latest checks killed concrete nonproductive paths rather than merely accumulating logs.
- For the next 2-3 turns, the history/loop-check process helps only if each step changes or explains one named field.
- Right next mode: code change.
- Process adjustment: the micro-scheduler patch must log one compact checkpoint line with owner, stop reason, TB count, tick-block completions, first-read seen, watched ticks, and edge state, so the next runtime has one primary artifact to judge.

## Next Step

- Narrow follow-up: implement one opt-in pre-first-read emulation-thread micro-scheduler/checkpoint. It must not fake interrupt state or weaken the strict B6 checker.
