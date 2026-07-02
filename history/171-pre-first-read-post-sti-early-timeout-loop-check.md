# Pre-First-Read Post-STI Early Timeout Loop Check

## Purpose

- One new fact this run was supposed to produce: whether another runtime is justified after the controlled post-STI retry repeated the same early timeout.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest controlled retry history `history/170-pre-first-read-post-sti-pump-controlled-retry.md`
- repeated early timeout at `read_lba=4609024`
- proposed field `post_sti_build_early_timeout_cause`
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Failed post-STI browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Controlled retry browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/browser-runtime.log`
- Prior history entry: `history/170-pre-first-read-post-sti-pump-controlled-retry.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_build_early_timeout_cause`.

## Findings

- Result: revise.
- Are we looping? Yes, if we keep running the current post-STI build.
- Narrowest next fact: `post_sti_build_early_timeout_cause`, meaning whether the current post-STI build perturbs early boot before dashboard read or whether unrelated harness instability remains plausible.
- Kill: port/origin drift as the explanation.
- Keep: the post-STI scheduler field remains untested.
- Revise: the immediate problem is build/code-shape regression before dashboard read, not runtime flakiness.
- Any runtime justified now? No.
- Better experiment: static code/log inspection comparing the last restored-boundary build against the post-STI build, focused on code active before entry-ready despite intended gating.
- Progress-method critique: the metrics still connect to strict B6 because the original target is the first-read tick gap blocking real browser `dashboard=xbe-executed`; main menu and game launch remain downstream. The current branch is now too runtime-heavy because two artifacts fail before the scheduler boundary. The next mode should be code/log inspection.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: before any future runtime, first prove the current build can preserve dashboard read/load with the mode enabled, or reduce the patch until that boundary is restored.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: stop rerunning this build; inspect code/logs for pre-entry side effects and restore dashboard read/load before scheduler validation.

## Next Step

- Narrow follow-up: static code/log inspection for `post_sti_build_early_timeout_cause`, especially mode parsing, before-interrupt call path, gate marker side effects, timer-pump site selection, and watched-state reads before entry-ready.
