# 220. Pre-TB Scheduler Build Sandbox Fail

## Purpose

Build the pre-TB scheduler owner patch in the existing WASM build directory.

The one field this run could change was
`pre_tb_scheduler_owner_build_status`.

## Command

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SKIP_WASM_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
scripts/docker-build-xemu-wasm.sh
```

## Inputs and Artifacts

- Source patch from `history/218-pre-tb-scheduler-owner-patch.md`
- Build directory: `build-wasm-pic`

## Loop-Guard Fields

- `pre_tb_scheduler_owner_build_status`

## Findings

The sandboxed build exited with status 1 before compiling:

```text
Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system
```

This is a sandbox/Podman access failure, not a compile result.

## Decision

`pre_tb_scheduler_owner_build_status=not-tested-sandbox-podman-fail`

## Next Step

Run the required loop check, then rerun the same build with escalated
permissions so Podman can access its runtime directory.
