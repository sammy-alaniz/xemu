# Timer Opportunity Wasm Build Compile Fail

## Purpose

- One new fact this run was supposed to produce: whether the C timer-opportunity diagnostic changes compile in the wasm browser build before any runtime probe.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$PATH \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Changed C diagnostics:
  - `xemu-xbe.c`
  - `xemu-xbe.h`
  - `ui/xemu-headless.c`
  - `util/main-loop.c`
- Existing wasm build directory: `build-wasm-pic`
- Output: command stdout/stderr only; build reached compilation.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, indirectly, by validating instrumentation needed for the next browser runtime diagnostic.

## Findings

- Result: fail at compile.
- The escalated build reached the compiler and failed in `xemu-xbe.c`.
- The error is a declaration-order issue: the forward declaration for `xemu_xbe_tcg_timer_pump_before_pfifo_gate_reason()` names `struct xemu_xbe_exec_context` before that struct tag is visible, so Clang treats the prototype and the later definition as conflicting incomplete types.
- No browser runtime run happened, and no B6 evidence changed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation artifact was produced.

## Decision

- Status: failed-run support
- Why: this is a real compile issue in the diagnostic code and must be fixed before any runtime probe.
- Independent critique used: yes

## Next Step

- Run the required post-history sub-agent loop check, then fix the C declaration ordering and rerun the wasm build-check.
