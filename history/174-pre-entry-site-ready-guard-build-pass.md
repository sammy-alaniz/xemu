# 174. Pre-Entry Site-Ready Guard Build Pass

## Purpose

Verify that the narrow pre-entry guard patch compiles in the browser/WASM build
without running the browser runtime.

## Commands

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SKIP_WASM_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
scripts/docker-build-xemu-wasm.sh
```

## Inputs / Artifacts

- Source patch in `xemu-xbe.c`
- Build directory: `build-wasm-pic`
- Output artifact: `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Field

- `pre_entry_site_ready_side_effect_reduced`

## Findings

The Podman-backed WASM build passed. The build recompiled
`libqemu-i386-softmmu.a.p/xemu-xbe.c.o` and relinked
`qemu-system-i386.js`.

The patch keeps the pre-first-read scheduler target unchanged and only moves the
cheap mode/trace/entry-ready/interval guard ahead of virtual-clock,
timer-expiry, CPU-context, and serviceability work.

## Decision

Build verification passed. No browser runtime was run in this step.

## Next Step

Run the required bounded loop check before deciding whether a single controlled
browser runtime retry is justified.
