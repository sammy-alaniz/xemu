# 175. Pre-Entry Site-Ready Runtime Loop Check

## Purpose

Run the required bounded sub-agent checkpoint after the pre-entry guard build
passed, before deciding whether a browser runtime retry is justified.

## Inputs / Artifacts

- `history/174-pre-entry-site-ready-guard-build-pass.md`
- Rebuilt `build-wasm-pic/qemu-system-i386.js`
- Proposed next run: one controlled browser runtime retry using the same
  known-good origin/port and diagnostic knobs as the prior controlled retry,
  with a new artifact directory.

## Loop-Guard Field

- `pre_entry_site_ready_side_effect_reduced`

## Findings

The sub-agent decision was `continue`.

One controlled runtime retry is justified because the source changed only the
suspected pre-entry side-effect path, while preserving the strict B6 checker and
the exact post-STI scheduler target.

Success criteria:

- dashboard read/load/entry-ready is restored at minimum
- preferably B4, section-map, PFIFO stream-idle, IRQ/IRET, or the useful
  post-service edge are restored too
- only after that boundary is restored should scheduler start, TCG timer-pump,
  or first-watch-read ticks be interpreted

Failure criterion:

- if the runtime again times out before dashboard read/load at or near
  `read_lba=4609024`, stop this branch and quarantine or roll back the
  micro-scheduler plumbing before further tuning

## Progress-Method Critique

Runtime evidence is still narrow enough for one more run because the code shape
changed to remove a concrete suspected perturbation. Further retries after
another early timeout would be too perturbation-driven.

## Decision

Continue with exactly one controlled browser runtime retry.

## Next Step

Run the controlled browser runtime once, write a new artifact directory, then
record the result before any further action.
