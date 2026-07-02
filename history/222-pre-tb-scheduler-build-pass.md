# 222. Pre-TB Scheduler Build Pass

## Purpose

Rerun the Podman WASM build with escalated permissions after the sandbox-only
failure in `history/220-pre-tb-scheduler-build-sandbox-fail.md`.

The one field this run could change was
`pre_tb_scheduler_owner_build_status`.

## Command

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SKIP_WASM_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
scripts/docker-build-xemu-wasm.sh
```

The command was run with escalated permissions because Podman needed access to
`/run/user/1000/libpod`.

## Inputs and Artifacts

- Source patch from `history/218-pre-tb-scheduler-owner-patch.md`
- Build directory: `build-wasm-pic`
- Output artifact: `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Fields

- `pre_tb_scheduler_owner_build_status`

## Findings

The build passed. The relevant build steps were:

- `Compiling C object libqemu-i386-softmmu.a.p/xemu-xbe.c.o`
- `Linking target qemu-system-i386.js`

## Decision

`pre_tb_scheduler_owner_build_status=pass`

## Next Step

Run the required loop check before deciding whether to run one
preservation-gated browser runtime for `browser_first_watch_read_ticks`.
