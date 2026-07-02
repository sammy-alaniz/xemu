# Pre-First-Read Post-STI Retry Loop Check

## Purpose

- One new fact this run was supposed to produce: whether one controlled retry is justified after the post-STI runtime timed out before dashboard read/load.

## Command(s)

```text
Sent a bounded B6 loop-check prompt to sub-agent 019f1e51-23ca-7e93-978c-89e48eb1dc60.

The prompt included:
- latest setup audit `history/168-pre-first-read-post-sti-setup-audit.md`
- fact that no setup mismatch was found
- proposed fields `post_sti_retry_reaches_b6_boundary` and `post_sti_first_read_predecessor_timer_pump`
- controlled retry proposal
- the required `Progress-Method Critique`
- required final decision: continue, revise, or stop
```

## Inputs And Artifacts

- Restored-boundary browser log: `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`
- Failed post-STI browser log: `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/browser-runtime.log`
- Prior history entry: `history/168-pre-first-read-post-sti-setup-audit.md`
- Fixture assumptions: no new emulation run; critique only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `post_sti_retry_reaches_b6_boundary`.

## Findings

- Result: continue.
- Are we looping? Not if the retry is controlled and judged first on reaching the B6 boundary.
- Narrowest next fact: `post_sti_retry_reaches_b6_boundary`.
- Kill: treating the 375-line timeout as evidence against the exact `0x80014f32` scheduler change.
- Keep: the post-STI timer-pump hypothesis remains untested.
- Revise: the immediate hypothesis is runtime stability; scheduler markers are meaningful only after dashboard read/load and B4/B5 preservation.
- One controlled retry justified now? Yes, exactly one.
- Better experiment? None before one controlled retry.
- Progress-method critique: the metrics still connect to strict dashboard execution because the exact scheduler field targets the first-read tick gap blocking real `dashboard=xbe-executed`; visible main menu and game launch remain downstream. The work is close to rerun-heavy, but this single retry is justified because the prior run failed before the field under test. The next mode should be runtime probing, not code change.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No new runtime was run.

## Decision

- Status: current
- Why: use one known-good origin/port and declare dashboard read/load as the first pass/fail gate before interpreting scheduler behavior.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: continue with one controlled runtime retry only; no code changes first.

## Next Step

- Narrow follow-up: run one controlled retry of the post-STI runtime using the known-good browser runtime port/origin. Primary field: `post_sti_retry_reaches_b6_boundary`.
