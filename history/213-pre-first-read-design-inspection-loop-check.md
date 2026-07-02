# 213. Pre-First-Read Design Inspection Loop Check

## Purpose

Run the required loop check after selecting `browser_first_watch_read_ticks` in `history/212-stable-baseline-next-field-selection.md`.

## Command

Sub-agent checkpoint sent to `019f1e51-23ca-7e93-978c-89e48eb1dc60`.

## Inputs and Artifacts

- `history/212-stable-baseline-next-field-selection.md`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Fields

- `browser_first_watch_read_ticks`
- next deterministic scheduler/timeline design viability

## Findings

The sub-agent agreed that `browser_first_watch_read_ticks` is the right non-redundant field, but chose `revise` for the immediate action.

Progress-method critique: this can put the work back on the path to strict dashboard execution and then main menu/game launch because it targets the actual browser/native divergence. The risk is repeating the micro-scheduler failure under a new label.

Required guard for the eventual code slice:

- opt-in only;
- no before-interrupt hook;
- no host-pump count tuning;
- no exact-PC IRQ defer;
- no manual interrupt mutation;
- no marker-only runtime;
- hard preservation gate for B4/B5/read/load/entry-ready/section-map plus `0x80030e84->0x80030f31`;
- one measurable success field: `browser_first_watch_read_ticks > 1`.

## Decision

Revise.

## Next Step

Perform a static design inspection only. Identify the exact emulation-thread hook, state machine, stop reasons, and preservation guards for a deterministic pre-first-read timeline. If that inspection cannot name a hook that avoids the quarantined before-interrupt behavior, reject the slice before code.
