# 316 - pcrtc final-window gate static patch

## Purpose

Implement the scoped default-off final-window PCRTC availability gate approved
by history/315. The field this patch can change is
`browser_pre_stream_vector_service_state`.

## Exact commands

```sh
git diff --check
git diff -- hw/xbox/nv2a/nv2a.c hw/xbox/nv2a/nv2a_int.h hw/xbox/nv2a/pfifo.c scripts/xbox-browser-runtime-smoke.sh
rg -n "pcrtc-prestream-gate|deterministic-prestream-wait-final-window|deterministic-prestream-final-window|nv2a_browser_deterministic_pcrtc_prestream_maybe_raise" hw/xbox/nv2a scripts -S
```

Code edits were made with `apply_patch`.

## Inputs and artifacts

- Plan and approval:
  - `history/314-pcrtc-final-window-gate-static-plan.md`
  - `history/315-pcrtc-final-window-gate-loop-check.md`
- Edited files:
  - `hw/xbox/nv2a/nv2a.c`
  - `hw/xbox/nv2a/nv2a_int.h`
  - `hw/xbox/nv2a/pfifo.c`
  - `scripts/xbox-browser-runtime-smoke.sh`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pcrtc_final_window_gate_patch_integrity`

## Findings

The static patch integrity check passed:

```text
git diff --check
```

returned no output and exit code 0.

The patch changes the default-off
`XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM` behavior:

- Browser `nv2a_vga_gfx_update()` no longer raises PCRTC vblank immediately
  after entry-ready when deterministic PCRTC prestream mode is enabled.
- That mode now suppresses regular browser vblank pre-stream with reason
  `deterministic-prestream-wait-final-window`.
- PFIFO calls
  `nv2a_browser_deterministic_pcrtc_prestream_maybe_raise()` after a method has
  been processed but before the last `DMA_GET` commit and before
  `pfifo_boot_trace_stream_idle_transition()`.
- The helper only allows one real PCRTC vblank raise when the final one-word
  PFIFO boundary is present:
  - `dma_get_after == dma_put`
  - `dma_get_before != dma_get_after`
  - `dma_put - dma_get_before == 4`
  - `available == 1`
  - `processed == 1`
  - FIFO/PGRAPH state is not blocked.
- The allow path mutates real PCRTC/NV2A IRQ state and emits the normal
  `nv2a=irq-source source=pcrtc op=vblank-raise` marker.
- A new bounded marker, `nv2a=pcrtc-prestream-gate`, reports action, reason,
  trigger, DMA state, PCRTC state, and PFIFO/PGRAPH wait state.

## Decision

Continue, but do not build or run until the required sub-agent loop check for
this patch has completed.

## Next step

Run the required bounded loop check with `Progress-Method Critique`. If it
returns `continue`, build the WASM target through the Podman path.
