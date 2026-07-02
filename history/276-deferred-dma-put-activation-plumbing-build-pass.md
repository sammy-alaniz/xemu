# 276 - Deferred DMA PUT Activation Plumbing Build Pass

## Purpose

Add and verify the minimal browser activation plumbing for the deferred
`NV_USER_DMA_PUT` observer without running a runtime experiment.

## Commands

```sh
git diff --check
node --check browser/xbox-boot/main.js
node --check browser/xbox-boot/worker.js
node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
bash -n scripts/xbox-browser-runtime-smoke.sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin XEMU_WASM_SKIP_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic XEMU_WASM_JOBS=4 scripts/docker-build-xemu-wasm.sh
```

## Inputs / Artifacts

- `browser/xbox-boot/main.js`
- `browser/xbox-boot/worker.js`
- `scripts/xbox-browser-runtime-smoke.sh`
- `scripts/xbox-browser-runtime-firefox-bidi.mjs`
- `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Field

- `deferred_dma_put_observer_activation_plumbing_build_status`

## Findings

- Added `nv2aUserDmaPutLimit` to browser trace option collection.
- Added worker fixture emission for
  `/xemu-fixtures/nv2a_user_dma_put_limit.txt`.
- Added `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` to both runtime harnesses.
- Added `trace_nv2a_user_dma_put_limit=...` to browser runtime summary output.
- `git diff --check`, JS/MJS syntax checks, and shell syntax check passed.
- Podman WASM build passed and linked `qemu-system-i386.js`.

## Decision

Activation plumbing now builds. This still does not prove runtime preservation
or observer activation in a real browser run.

## Next Step

Run the required bounded sub-agent loop check before any runtime. The next
possible field is `deferred_dma_put_observer_runtime_preservation`.
