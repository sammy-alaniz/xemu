# 210. DMA_PUT Marker Quarantine Build

## Purpose

Quarantine the perturbing DMA_PUT marker by making it opt-in disabled by default, then run build-only verification. No runtime was launched.

## Code Change

Modified `hw/xbox/nv2a/user.c`:

```c
#define XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 0
```

This preserves the marker code for explicit opt-in use through `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT`, but prevents it from emitting in normal browser or native runs.

## Command

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin XEMU_SKIP_WASM_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic scripts/docker-build-xemu-wasm.sh
```

## Inputs and Artifacts

- Source:
  `hw/xbox/nv2a/user.c`
- Build target:
  `qemu-system-i386.js`

## Loop-Guard Fields

- `dma_put_marker_default_quarantined=yes`

## Findings

The Podman WASM build passed.

Relevant output:

```text
[4/5] Compiling C object libqemu-i386-softmmu.a.p/hw_xbox_nv2a_user.c.o
[5/5] Linking target qemu-system-i386.js
```

## Decision

DMA_PUT marker work is quarantined. Do not rerun the marker runtime. The next branch should return to the stable pre-service CPU/tick boundary.

## Next Step

Run the required loop check before selecting the next stable-baseline target.
