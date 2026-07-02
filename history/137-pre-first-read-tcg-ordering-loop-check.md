# 137. Pre-first-read TCG ordering loop check

## Purpose

Run the required bounded loop check after the static ordering audit showed the current TCG pump path is a nonproducer for the watched tick word.

## Loop-Guard Field

- `pre_first_read_tick_accumulation_owner`

## Exact Command

Sub-agent loop check sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `AGENTS.md`
- `goal.md`
- `history/136-pre-first-read-tcg-ordering-audit.md`
- Same-origin browser artifact:
  `build-real-b3-matrix/browser-tcg-post-pfifo-pre-first-read-v2-same-origin/browser-runtime-combined.log`
- Native reference:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`

## Findings

The sub-agent reported:

- Continuing to iterate on the current `pit-post-pfifo-pre-first-read` TCG pump predicate would be looping.
- The next boundary-changing fact is the actual owner/order point that can accumulate ticks before browser reaches `0x80014f32->0x80030e84`.
- The field should be `pre_first_read_tick_accumulation_owner`, with `browser_first_watch_read_ticks` as the runtime guard.
- Kill the current after-TB TCG pump predicate path as a way to move `pre_service_browser_first_watch_read_ticks`.
- Keep strict B6 unchanged and keep same-origin port `8846` as the valid browser harness for this slice.
- Revise the scheduler work to move earlier than the observed read and focus on why native reaches the analogous read with 136 ticks and no pending interrupt while browser reaches it with 0 ticks and pending interrupt.
- A better next step is a narrow design/code inspection comparing existing deterministic/ready-edge machinery against native/browser pre-read ordering, specifically where timer/PIC service can happen before `0x80014f32->0x80030e84` while preserving the useful post-service edge.

## Progress-Method Critique

The sub-agent reported:

- The work is still tied to Xbox main menu and game launch because strict browser B6 is the immediate gate, but this slice is close to diagnostic churn.
- The last audit was useful because it killed a concrete nonproducer path.
- The history/loop-check process helped by stopping another TCG predicate runtime.
- For the next 2-3 turns, the process should require the next code change to state the exact pre-read ordering point it moves, the baseline edge it must preserve, and the fallback artifact if it regresses.

## Decision

`revise`

## Next Step

Do a narrow design/code inspection of the deterministic and ready-edge timer machinery to identify one pre-read tick accumulation owner/order point. Do not run another browser runtime before that inspection names the exact field to change.
