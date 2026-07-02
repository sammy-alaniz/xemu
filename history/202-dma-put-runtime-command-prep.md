# 202. DMA_PUT Runtime Command Prep

## Purpose

Prepare the exact one-runtime command authorized by `history/201-dma-put-marker-runtime-loop-check.md` without launching the runtime yet. The field remains `nv_user_dma_put_writer_cpu_context`.

## Commands

```sh
rg -n 'ready-edge-host4|XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_MODE|xbox-b6-current-boundary|browser-memory-watch-write-0x3a890-ready-edge-host4' goal.md
rg -n 'firefox|bidi|browser-runtime|headless|ready-edge|memory-watch-write' scripts -g '*.sh' -g '*.py'
ls scripts | rg 'browser|xbox|b6|runtime|firefox|playwright'
ls build-real-b3-matrix | rg 'ready-edge-host4'
rg -n -m 40 'ready-edge-host4|pfifo-ready-edge-qemu-pump|XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_ACCESS|XEMU_BOOT_TRACE_XBE_MEMORY_WATCH_PHYS|XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT' history goal.md xbox-browser-boot-plan.md
rg -n -m 80 'browser-memory-watch-write-0x3a890-ready-edge-host4-v1|pfifo-ready-edge-qemu-pump|xbox-browser-runtime-firefox-bidi' history
sed -n '1,220p' scripts/xbox-browser-runtime-smoke.sh
sed -n '1,180p' scripts/xbox-browser-runtime-firefox-bidi.mjs
sed -n '10,120p' history/50-pfifo-kick-source-runtime.md
```

## Inputs and Artifacts

- `goal.md`
- `scripts/xbox-browser-runtime-smoke.sh`
- `scripts/xbox-browser-runtime-firefox-bidi.mjs`
- `history/50-pfifo-kick-source-runtime.md`
- Stable baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Fields

- `nv_user_dma_put_writer_cpu_context`
- runtime shape preservation against ready-edge host4

## Findings

`goal.md` identifies the stable browser CPU-flow baseline as:

```text
build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

The exact comparable ready-edge host4 runtime command shape is documented in `history/50-pfifo-kick-source-runtime.md`. It uses:

- real runtime mode;
- Firefox BiDi;
- `build-wasm-pic`;
- PCRTC vblank mode `off`;
- memory watch physical `0x0003a890`;
- memory watch access `write`;
- ready-edge host pump mode `pfifo-ready-edge-qemu-pump`;
- host pump progress limit `4`;
- TCG timer pump interval `0`;
- TCG timer pump mode `pit-after-idle-full`;
- IRQ logging gated after PFIFO empty.

For the upcoming runtime, the only intended diagnostic addition is:

```text
XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT=16
```

The output artifact should be a new directory rather than overwriting existing evidence:

```text
build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-user-dma-put-v1/
```

## Decision

Use the `history/50` runtime shape with a fresh output directory, a fresh local port, and only the new DMA_PUT marker limit added.

## Next Step

Run the required loop check for this command-prep entry, then launch the one authorized runtime if the loop check continues.
