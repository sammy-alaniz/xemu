# 178. Before-Interrupt Quarantine Build Pass

## Purpose

Verify that the micro-scheduler before-interrupt quarantine patch compiles in
the browser/WASM build without running the browser runtime.

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

- `micro_scheduler_branch_quarantined_restores_dashboard_read_load`

## Findings

The Podman-backed WASM build passed. The build recompiled
`libqemu-i386-softmmu.a.p/xemu-xbe.c.o` and relinked
`qemu-system-i386.js`.

The patch disables the pre-first-read micro-scheduler before-interrupt hook by
making `xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt()` return `false`.
It does not weaken the strict B6 checker and does not add any new acceptance
path for `dashboard=xbe-executed`.

## Decision

Build verification passed. No browser runtime was run in this step.

## Next Step

Run the required bounded loop check before deciding whether one restoration
runtime is justified.
