# 230. Pre-TB Quarantine Build Pass

## Purpose

Run the build-only verification approved by
`history/229-pre-tb-quarantine-build-loop-check.md`.

The one field this run could change was
`pre_tb_scheduler_branch_quarantined_build_status`.

## Command

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_SKIP_WASM_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
scripts/docker-build-xemu-wasm.sh
```

The command was run with escalated permissions because Podman needs access to
`/run/user/1000/libpod`.

## Inputs and Artifacts

- Source patch from `history/228-pre-tb-scheduler-quarantine-patch.md`
- Build directory: `build-wasm-pic`
- Output artifact: `build-wasm-pic/qemu-system-i386.js`

## Loop-Guard Fields

- `pre_tb_scheduler_branch_quarantined_build_status`

## Findings

The build passed. The relevant build steps were:

- `Compiling C object libqemu-i386-softmmu.a.p/xemu-xbe.c.o`
- `Linking target qemu-system-i386.js`

## Decision

`pre_tb_scheduler_branch_quarantined_build_status=pass`

The pre-TB scheduler branch is quarantined again at build level. No runtime was
run for the quarantine, per `history/229`.

## Next Step

Run the required loop check before selecting any next B6 target from the stable
ready-edge host4 baseline.
