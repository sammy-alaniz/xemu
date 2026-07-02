# Call Chain Trace Instrumentation

## Purpose

- One new fact this run was supposed to produce:
  whether an opt-in, one-shot call-chain trace can expose the broad path from
  `main()` through TCG execution to
  `xemu_xbe_boot_trace_mark_executed()` without weakening the B6 contract or
  flooding hot CPU loops.

## Command(s)

```sh
git diff --check -- ui/xemu-headless.c system/vl.c \
  accel/tcg/tcg-accel-ops.c accel/tcg/cpu-exec.c xemu-xbe.c
rg -n "CALL_CHAIN|XEMU_BOOT_TRACE_CALL_CHAIN|xemu_call_chain_trace" \
  ui/xemu-headless.c system/vl.c accel/tcg/tcg-accel-ops.c \
  accel/tcg/cpu-exec.c xemu-xbe.c
command -v ninja
command -v meson
command -v samu
command -v ninja-build
find build-docker-b6-pfifo-boundary build-docker build-wasm build-wasm-pic \
  build-docker-b6-xbe-scan -maxdepth 4 -type f -perm -u+x \
  \( -name 'xemu*' -o -name 'qemu-system-i386' \) -print
```

## Inputs And Artifacts

- Baseline native log: not used; no emulation run was started.
- Baseline browser log: not used; no browser runtime was started.
- Output directory/log: source edits only, gated by `XEMU_BOOT_TRACE_CALL_CHAIN=1`.
- Fixture assumptions: none.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `call_chain_trace_reaches_mark_executed_attempt`.

## Findings

- Result: source instrumentation was added and static validation passed.
- Important marker/comparator lines:
  - `CALL_CHAIN started main!`
  - `CALL_CHAIN started qemu_main_thread!`
  - `CALL_CHAIN started qemu_init!`
  - `CALL_CHAIN started qemu_init_board!`
  - `CALL_CHAIN started machine/device/CPU setup!`
  - `CALL_CHAIN started qemu_main_loop!`
  - `CALL_CHAIN started TCG vCPU execution loop!`
  - `CALL_CHAIN started tcg_cpu_exec!`
  - `CALL_CHAIN started cpu_exec!`
  - `CALL_CHAIN started cpu_exec_loop!`
  - `CALL_CHAIN started cpu_loop_exec_tb!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_observe_exec!`
  - `CALL_CHAIN started xemu_xbe_boot_trace_mark_executed!`
- `git diff --check` reported no whitespace errors for the edited files.
- Build/run verification could not be completed in this shell because `ninja`,
  `meson`, `samu`, and `ninja-build` were not installed. Existing
  `qemu-system-i386` binaries were present, but they predated the source edit
  and would not test the new markers.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not measured; no emulation run was started and the trace is env-gated.

## Decision

- Status: historical support
- Why: this is explanatory instrumentation for a human-requested call-chain
  trace, not B6 completion evidence.
- Independent critique used: no

## Next Step

- Narrow follow-up:
  build a current binary in an environment with `ninja` or `meson`, then run a
  short `XEMU_BOOT_TRACE_CALL_CHAIN=1` headless smoke to confirm the emitted
  call-chain order reaches `xemu_xbe_boot_trace_observe_exec()` and, after
  XBE load, `xemu_xbe_boot_trace_mark_executed()`.
