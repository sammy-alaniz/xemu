# 192. PFIFO Scheduler Source-Tag Build Pass

## Purpose

Verify that the existing marker-only PFIFO scheduler source-tag worktree changes
build into the browser/WASM artifact before any runtime.

## Commands

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SKIP_WASM_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
scripts/docker-build-xemu-wasm.sh
```

## Inputs / Artifacts

- Worktree PFIFO/PGRAPH/user/nv2a source-tag changes
- Build directory: `build-wasm-pic`
- Output artifact: `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Field

- `pfifo_scheduler_source_tags_build_status`

## Findings

The Podman-backed browser/WASM build passed and relinked
`qemu-system-i386.js`.

Ninja did not recompile `hw/xbox/nv2a/pfifo.c` in this invocation; it only
compiled `xemu-version.c` and relinked. That implies the PFIFO source-tag object
was already considered up to date by the existing build directory.

No browser runtime was run.

## Decision

Build verification passed.

## Next Step

Run the required bounded loop check before deciding whether one runtime focused
only on `first_kick_after_last_opportunity_source` is justified.
