# Edge Decision Skip Marker Build Sandbox Fail

## Purpose

- One new fact this run was supposed to produce: whether the low-impact `edge-decision-skip` marker patch compiles in the podman-backed WASM build.

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
- Output directory/log: none; build failed before compilation.
- Fixture assumptions: sandboxed command using podman wrapper.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: compile viability of the `edge_trace_marker_absence_reason` diagnostic.

## Findings

- Result: failed before build/compile.
- Error: `Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system`.
- `git diff --check` passed before this build attempt.
- No emulator artifact was produced, and the patch was not compiled by this run.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not measured; no runtime was started.

## Decision

- Status: failed run
- Why: this is a sandbox/podman setup failure, not evidence about the code patch.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then rerun the same podman build with sandbox escalation.
