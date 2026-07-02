# Pre-First-Read Post-STI Early Timeout Loop Check

## Purpose

- One new fact this run was supposed to produce: whether to retry the post-STI scheduler runtime after an early timeout, inspect setup/log differences, or stop the branch.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest failed runtime history `history/166-pre-first-read-post-sti-pump-runtime-early-timeout.md`
- fact that the run failed before dashboard read/load and before scheduler markers
- proposed next field `post_sti_runtime_retry_or_setup_issue`
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Failed post-STI browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Prior history entry: `history/166-pre-first-read-post-sti-pump-runtime-early-timeout.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_runtime_retry_or_setup_issue`.

## Findings

- Result: revise.
- Are we looping? Not yet, but a blind retry risks looping.
- Narrowest next fact: `post_sti_runtime_retry_or_setup_issue`, meaning whether the early timeout was a one-off or a repeatable setup/code regression preventing the artifact from reaching the B6 boundary.
- Kill: interpreting the early timeout as a scheduler result.
- Keep: the exact `0x80014f32` post-STI pump hypothesis remains untested.
- Revise: restore confidence that the same command shape can reach dashboard read/load and PFIFO stream-idle before another scheduler evaluation.
- Retry justified now? No; setup/log inspection first.
- Better experiment: no-emulation comparison between the 375-line log and restored-boundary same-origin artifacts, focusing on port/origin, asset setup, block backing, early IDE/BMDMA progress, fixture state, and first divergence after `read_lba=4609024`.
- Progress-method critique: the metrics still connect to strict dashboard execution because the untested field targets the first-read tick gap. The work is at risk of rerun churn because multiple recent artifacts failed before the intended boundary. The next mode should be static log/setup inspection.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: do not spend another runtime until a quick setup/log comparison determines whether a controlled retry is justified.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: separate harness/setup failures from scheduler evidence. Before each scheduler runtime, require a short same-origin readiness check in the history entry.

## Next Step

- Narrow follow-up: compare the failed post-STI runtime log against the restored-boundary browser artifact without running emulation. Primary field: `post_sti_runtime_retry_or_setup_issue`.
