# 318 - pcrtc final-window gate wasm build

## Purpose

Validate the scoped final-window PCRTC gate patch compiles in the browser/WASM
target. The field is `pcrtc_final_window_gate_patch_integrity`.

## Exact commands

Sandboxed attempt:

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

Escalated retry after Podman runtime-state access failed in the sandbox:

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs and artifacts

- Edited source from history/316:
  - `hw/xbox/nv2a/nv2a.c`
  - `hw/xbox/nv2a/nv2a_int.h`
  - `hw/xbox/nv2a/pfifo.c`
  - `scripts/xbox-browser-runtime-smoke.sh`
- Build output:
  - `build-wasm-pic/qemu-system-i386.js`

## Loop-guard fields

- `pcrtc_final_window_gate_patch_integrity`
- `browser_pre_stream_vector_service_state`

## Findings

The sandboxed attempt failed before building because Podman could not update
its runtime state:

```text
Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system
```

The escalated retry passed. The build compiled the touched NV2A/PFIFO/browser
objects and linked:

```text
[24/24] Linking target qemu-system-i386.js
```

This proves build integrity only. It does not prove the runtime boundary,
strict B6, dashboard execution, menu visibility, or game launch.

## Decision

Continue. The next step may be the single targeted browser runtime attempt
only after the required sub-agent loop check for this build result.

## Next step

Run the bounded loop check with `Progress-Method Critique`. If it returns
`continue`, run exactly one final-window PCRTC browser runtime targeting
`browser_pre_stream_vector_service_state`.
