# 172. Pre-Entry Site-Ready Inspection

## Purpose

Identify why the current post-STI pre-first-read scheduler build repeatedly times
out before dashboard XBE read/load evidence, and avoid another runtime run until
the pre-entry behavior is understood.

## Commands

```sh
sed -n '1968,2068p' xemu-xbe.c
sed -n '2636,2655p' xemu-xbe.c
sed -n '1188,1220p' accel/tcg/cpu-exec.c
git diff -- xemu-xbe.c accel/tcg/cpu-exec.c xemu-xbe.h | rg -n "pre_first_read|before_interrupt|after_tb|qemu_clock|capture_exec_context|entry_ready|HF_INHIBIT|FIRST_READ"
```

## Inputs / Artifacts

- Current working tree after `browser-pre-first-read-post-sti-pump-retry-v1`
- `xemu-xbe.c`
- `accel/tcg/cpu-exec.c`
- `xemu-xbe.h`
- Prior failed artifacts:
  - `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-v1/`
  - `build-real-b3-matrix/browser-pre-first-read-post-sti-pump-retry-v1/`

## Loop-Guard Field

- `post_sti_build_early_timeout_cause`

## Findings

The exact post-STI scheduler condition remains untested because both runtime
attempts stop before dashboard read/load and before any scheduler, gate, or TCG
timer-pump marker appears.

The static inspection found that
`xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_site_ready()` is called from
the before-interrupt and after-TB paths, and it performs work before proving the
dashboard entry-ready gate:

- reads virtual clock state and timer expiry
- captures the current CPU execution context
- evaluates serviceability
- only later uses the entry-ready state as part of the final readiness decision

Because the repeated runtime failure occurs before dashboard read/load and
entry-ready, this pre-entry predicate work is the narrowest plausible code-shape
risk to remove before any further runtime attempt.

## Decision

Revise before running again. Add a cheap early guard so the pre-first-read
scheduler predicate returns before clock/context/serviceability work unless the
mode is selected, trace is enabled, the dashboard is entry-ready, and the
configured interval is usable.

## Next Step

Run the required bounded loop check with a progress-method critique section.
If it agrees, patch the early guard and build before any runtime retry.
