# Pre-First-Read Micro-Scheduler Build Sandbox Fail

## Purpose

- One new fact this run was supposed to produce: whether the opt-in pre-first-read micro-scheduler patch compiles in the browser/WASM podman build.

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
- Output directory/log: no build artifact; podman failed before compiler start
- Fixture assumptions: browser/WASM builds must use the podman container path.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain: `build_verification_status`

## Findings

- Result: failed before compilation.
- Important output:
  `Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system`
- This did not test C compilation and produced no runtime evidence.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not tested.

## Decision

- Status: failed run
- Why: the managed sandbox blocked podman runtime setup, so the next action is an escalated retry of the same build command.
- Independent critique used: no

## Next Step

- Narrow follow-up: run the required loop check, then retry the exact podman build with escalation. The build retry can only change `build_verification_status`.
