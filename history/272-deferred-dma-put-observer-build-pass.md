# 272 - Deferred DMA PUT Observer Build Pass

## Purpose

Implement and build-check the safer deferred `NV_USER_DMA_PUT` observer without
running a browser/native runtime experiment.

## Commands

```sh
git diff --check
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin XEMU_WASM_SKIP_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic XEMU_WASM_JOBS=4 scripts/docker-build-xemu-wasm.sh
```

## Inputs / Artifacts

- `hw/xbox/nv2a/user.c`
- `hw/xbox/nv2a/nv2a_int.h`
- `hw/xbox/nv2a/nv2a.c`
- `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Field

- `deferred_dma_put_observer_build_status`

## Findings

- Replaced the previous `nv2a=user-dma-put` marker path that captured CPU/XBE
  state from inside `user_write`.
- The new path caches trace config during NV2A memory init, captures only a
  small DMA snapshot while `pfifo.lock` is held, runs the PFIFO kick normally,
  unlocks, then emits the capped marker outside the lock.
- The observer remains default-off with limit `0`; opt-in limit can come from
  `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` or
  `nv2a_user_dma_put_limit.txt` fixtures.
- `git diff --check` passed.
- Podman WASM build passed and linked `qemu-system-i386.js`.

## Decision

The build-only safety gate passed. This does not prove runtime preservation or
B6 progress; it only proves the safer observer compiles.

## Next Step

Run the required bounded sub-agent loop check before any runtime experiment or
additional code change. The next possible field is
`deferred_dma_put_observer_runtime_preservation`, but only if the loop check
approves a tightly capped runtime run.
