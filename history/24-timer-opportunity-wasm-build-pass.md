# Timer Opportunity Wasm Build Pass

## Purpose

- One new fact this run was supposed to produce: whether the timer-opportunity C diagnostics compile in the wasm browser build after the declaration-order fix.

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
- Output artifact: rebuilt `build-wasm-pic/qemu-system-i386.js` and associated wasm build outputs.

## Expected Field(s)

- `pre_service_browser_first_watch_read_ticks`, indirectly, by enabling the runtime diagnostic that can explain the field.

## Findings

- Result: pass.
- The wasm build completed after regenerating version headers, compiling `xemu-version.c`, compiling `xemu-xbe.c`, and linking `qemu-system-i386.js`.
- This validates the declaration-order fix and the C diagnostic instrumentation at compile time.
- No browser runtime run happened yet, so no B6 evidence changed.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? No emulation artifact was produced.

## Decision

- Status: current support
- Why: the instrumentation is now buildable, so the next allowed step is exactly one current ready-edge-host4 browser runtime diagnostic with timer-opportunity evidence.
- Independent critique used: yes

## Next Step

- Run the required post-history sub-agent loop check, then run one current ready-edge-host4 browser diagnostic if the critique still says continue.
