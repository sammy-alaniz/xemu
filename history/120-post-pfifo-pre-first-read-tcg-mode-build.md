# Post PFIFO Pre First Read TCG Mode Build

## Purpose

- One new fact this code/build step was supposed to produce:
  `pre_first_read_tcg_checkpoint_active`, specifically whether the codebase now
  has one opt-in emulation-thread-owned TCG checkpoint mode that can later be
  runtime-tested without relying on browser host-pump ownership or exact-PC IRQ
  deferral.

## Command(s)

```sh
apply_patch <<'PATCH'
# Add a diagnostic-only TCG timer pump mode:
# XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-post-pfifo-pre-first-read
#
# The mode is parsed in xemu_xbe_tcg_timer_pump_mode(), is PIT-only, and its
# readiness helper requires:
# - PFIFO stream-idle transition observed
# - current wait state is PFIFO empty
# - no tick-block completion yet
# - no edge-decision marker yet
# - CPU context is the existing IRQ-serviceable idle PC with no pending IRQ
# - virtual timers exist and are expired
# - delivery attempts are below XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT
PATCH

git diff --check -- xemu-xbe.c

nl -ba xemu-xbe.c | sed -n '1268,1328p'
nl -ba xemu-xbe.c | sed -n '1490,1548p'
nl -ba xemu-xbe.c | sed -n '1864,1922p'
nl -ba xemu-xbe.c | sed -n '1948,1968p'

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Source file changed: `xemu-xbe.c`
- Build artifact:
  `build-wasm-pic/qemu-system-i386.js`
- Prior approval:
  `history/119-emulation-thread-checkpoint-site-loop-check.md`
- Fixture assumptions: build only; no browser runtime or emulation validation
  started.

## Expected Field(s)

- Loop-guard field(s) this code/build step could change or explain:
  `pre_first_read_tcg_checkpoint_active`.

## Findings

- Result: the new opt-in TCG pump mode is present:
  `pit-post-pfifo-pre-first-read`, with aliases
  `pit-after-pfifo-pre-first-read`, `post-pfifo-pre-first-read`, and
  `pre-first-read`.
- The mode is PIT-only, so it uses the existing
  `qemu_clock_run_timers_with_attrs_limit(... QEMU_TIMER_ATTR_XEMU_TCG_PUMP
  ..., 1)` path instead of `qemu_clock_run_all_timers()`.
- The readiness helper is gated to:
  - PFIFO stream-idle transition observed.
  - Current NV2A wait state is PFIFO empty.
  - No normal `tick-block=complete` marker yet.
  - No `edge-decision` marker yet.
  - Existing serviceable idle-loop CPU context with no pending interrupt.
  - Virtual timers exist and are expired.
  - Delivery attempts are capped by
    `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT`.
- The mode does not manually mutate `interrupt_request`, `exit_request`, or
  `cpu->neg.icount_decr.u16.high`.
- `git diff --check -- xemu-xbe.c` passed.
- First sandboxed podman build failed before compiling because podman could not
  set up `/run/user/1000/libpod` in the sandbox:
  `Failed to obtain podman configuration: set sticky bit on: chmod
  /run/user/1000/libpod: read-only file system`.
- Rerunning the same command with sandbox escalation passed:
  `Compiling C object ... xemu-xbe.c.o` and
  `Linking target qemu-system-i386.js`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured. This was a code/build step only.

## Decision

- Status: current code candidate.
- Why: the code now provides exactly one opt-in emulation-thread checkpoint
  mode approved by `history/119`. It is not active by default and is ready for
  one bounded runtime validation only after the required loop check.
- Independent critique used: yes.
- If yes, critique decision: continue.
- If yes, critique summary: `history/119` approved one diagnostic-only TCG pump
  mode in the existing after-`cpu_tb_exec()` path, gated to
  post-PFIFO/pre-first-read state, capped, stopped by normal tick-block
  completion, and relying on normal CPU interrupt handling.

## Progress-Method Critique

- This code step moves toward strict browser dashboard execution by replacing
  host-poll timing with an emulation-thread checkpoint that can directly test
  the current tick/CPU ordering boundary.
- It avoids exact-PC IRQ deferral and does not weaken the strict B6 detector.
- It is still diagnostic until a runtime proves the field moves, so it should
  not be promoted without `browser_first_watch_read_ticks` and post-service
  edge evidence.
- The next mode should be one bounded runtime validation, not more code
  expansion.
- Process adjustment for the next 2-3 turns: judge the next run first on
  whether this mode emits `tcg=timer-pump mode=pit-post-pfifo-pre-first-read`,
  then on `browser_first_watch_read_ticks` and preservation of
  `0x80030e84->0x80030f31`.

## Next Step

- Narrow follow-up: run the required loop check. If approved, run exactly one
  browser validation using the new mode, with host-pump counts unchanged and no
  exact-PC defer behavior.
