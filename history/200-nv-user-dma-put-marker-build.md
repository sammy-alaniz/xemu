# 200. NV_USER DMA_PUT Marker Build

## Purpose

Add the approved marker-only diagnostic for `nv_user_dma_put_writer_cpu_context` and perform the approved build-only verification. No runtime was launched.

## Code Change

Modified `hw/xbox/nv2a/user.c` only.

The new marker emits:

```text
BOOT_MARK b6 nv2a=user-dma-put ...
```

It is gated by the existing boot trace context and `xemu_xbe_boot_trace_loaded()`, has its own local limit via `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT`, and logs:

- channel and current PFIFO channel;
- NV_USER address, offset, write size, and raw value;
- `dma_get`, old `DMA_PUT`, new `DMA_PUT`;
- old/new `dma_to_put`;
- loaded, entry-ready, dashboard-observed, and executed state;
- guest CPU context when available: source, mode, CPL, EIP, CS, ESP, EFLAGS, interrupt enable/inhibit state, interrupt request, halted/exit/exception state.

The patch does not change PFIFO state semantics, scheduling, timer delivery, the B6 checker, or broad marker limits. It only observes the `NV_USER_DMA_PUT` path after `DMA_PUT` is updated and before the existing `pfifo_kick_with_source()` call.

## Command

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin XEMU_SKIP_WASM_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic scripts/docker-build-xemu-wasm.sh
```

## Inputs and Artifacts

- Source: `hw/xbox/nv2a/user.c`
- Build dir: `build-wasm-pic`
- Output target: `qemu-system-i386.js`

## Loop-Guard Fields

- `nv_user_dma_put_writer_cpu_context`
- `first_nv_user_dma_put_writer_marker_coverage`

## Findings

The Podman WASM build passed.

Relevant build output:

```text
[4/5] Compiling C object libqemu-i386-softmmu.a.p/hw_xbox_nv2a_user.c.o
[5/5] Linking target qemu-system-i386.js
```

## Decision

The marker-only patch compiles. Per the previous loop check, do not run a browser runtime yet.

## Next Step

Run the required loop check with progress-method critique before any runtime or further code change.
