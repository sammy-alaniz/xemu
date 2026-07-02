# Pre-First-Read Micro-Scheduler Compile Fail

## Purpose

- One new fact this run was supposed to produce: whether the opt-in pre-first-read micro-scheduler patch compiles in the browser/WASM podman build after escalating past the podman sandbox boundary.

## Command(s)

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
  XEMU_WASM_SKIP_IMAGE_BUILD=1 \
  XEMU_WASM_BUILD_DIR=build-wasm-pic \
  XEMU_WASM_JOBS=4 \
  scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: build output in terminal; no successful build artifact
- Fixture assumptions: podman escalation is required for browser/WASM build access in this environment.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `build_verification_status`

## Findings

- Result: failed at C compilation.
- The build reached `emcc` and compiled multiple objects before failing at `xemu-xbe.c`.
- Important compiler line:
  `../xemu-xbe.c:482:26: error: expected ';' at end of declaration list`
- Cause: a C struct field still has an invalid in-place initializer:
  `bool watch_value_read = false;`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested; this was compile-only.

## Decision

- Status: failed run
- Why: this is a mechanical C syntax error, not evidence against the scheduler design.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then remove the invalid struct-field initializer and retry build verification. The fix can only change `build_verification_status`.
