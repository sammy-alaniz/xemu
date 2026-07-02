# 314 - pcrtc final-window gate static plan

## Purpose

Create the no-runtime static patch plan requested by the history/313 loop
check. The planned field is `browser_pre_stream_vector_service_state`, with the
supporting explanation field
`native_pre_stream_serviceable_state_browser_mapping`.

## Exact commands

```sh
sed -n '1,460p' goal.md
sed -n '1,240p' history/312-native-pre-stream-serviceable-design-proposal.md
sed -n '1,220p' history/313-native-pre-stream-serviceable-loop-check.md
git status --short
rg -n "typedef struct XemuXbeBootTraceNv2aWaitState|XemuXbeBootTraceNv2aWaitState|struct xemu_xbe_nv2a_wait_snapshot|xemu_xbe_nv2a_wait_snapshot_is" xemu-xbe.c xemu-xbe.h hw/xbox/nv2a -S
rg -n "pfifo-window|puller-method-done|pusher-puller-done|pusher-empty|stream-idle-transition|dma_get|dma_put" xemu-xbe.c hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/user.c hw/xbox/nv2a/nv2a.c -S
rg -n "deterministic_pcrtc|XEMU_BROWSER_BOOT.*PCRTC|pcrtc_prestream|pcrtc-vblank" hw/xbox/nv2a/nv2a.c xemu-xbe.c ui/xemu-headless.c browser/xbox-boot -S
rg -n "XEMU_BROWSER_BOOT_PCRTC|pcrtc_vblank|pcrtc-prestream|PCRTC" scripts browser/xbox-boot -S
nl -ba xemu-xbe.h | sed -n '180,235p'
nl -ba xemu-xbe.c | sed -n '240,360p'
nl -ba xemu-xbe.c | sed -n '620,990p'
nl -ba hw/xbox/nv2a/pfifo.c | sed -n '280,390p'
rg -n "BOOT_MARK b6 pfifo=window|BOOT_MARK b6 pfifo=stream-idle|BOOT_MARK b6 nv2a=pcrtc-vblank-gate|BOOT_MARK b6 nv2a=irq-source.*source=pcrtc|BOOT_MARK b6 cpu=hard-irq-service.*intno=0x30|BOOT_MARK b6 memory-watch" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | tail -n 120
rg -n "BOOT_MARK b6 pfifo=window|BOOT_MARK b6 pfifo=stream-idle|BOOT_MARK b6 nv2a=irq-source.*source=pcrtc|BOOT_MARK b6 cpu=hard-irq-service.*intno=0x30|BOOT_MARK b6 memory-watch" build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log | sed -n '1,160p'
nl -ba hw/xbox/nv2a/pfifo.c | sed -n '1080,1390p'
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '880,1038p'
nl -ba hw/xbox/nv2a/nv2a.c | sed -n '1,80p'
nl -ba hw/xbox/nv2a/nv2a_int.h | sed -n '1,120p'
sed -n '315,365p' browser/xbox-boot/worker.js
sed -n '575,595p' browser/xbox-boot/main.js
sed -n '60,105p' scripts/xbox-browser-runtime-smoke.sh
sed -n '315,360p' scripts/xbox-browser-runtime-smoke.sh
rg -n "nv2a=pcrtc-vblank-gate" build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log | head -n 80
```

No emulator runtime was started and no source files were edited for this plan.

## Inputs and artifacts

- Current goal:
  - `goal.md`
- Latest design and loop-check:
  - `history/312-native-pre-stream-serviceable-design-proposal.md`
  - `history/313-native-pre-stream-serviceable-loop-check.md`
- Stable browser CPU-flow baseline:
  - `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Native strict execution/reference baseline:
  - `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Planned edit surface:
  - `hw/xbox/nv2a/nv2a.c`
  - `hw/xbox/nv2a/nv2a_int.h`
  - `hw/xbox/nv2a/pfifo.c`
  - `scripts/xbox-browser-runtime-smoke.sh`

## Loop-guard fields

- `browser_pre_stream_vector_service_state`
- `native_pre_stream_serviceable_state_browser_mapping`
- `pre_service_browser_first_watch_read_ticks`
- `post_service_watch_edge`

## Static facts

The stable browser final PFIFO window has a concrete one-word boundary:

- Before stream-idle:
  - `pfifo=window op=puller-method` at `dma_get=0x03881314`,
    `dma_put=0x03881318`, `method=0x1d90`.
  - `pfifo=window op=puller-method-done` and
    `op=pusher-puller-done` preserve that one-word remaining state.
- Stream-idle transition:
  - `pfifo=stream-idle-transition` moves
    `dma_get_before=0x03881314` to `dma_get_after=0x03881318`,
    matching `dma_put=0x03881318`.
- Current browser vector `0x30` service happens only after stream-idle from
  `pfifo-window/pusher-empty`, with `pcrtc_pending=0` and
  `pcrtc_enabled=1`.

The native side has the missing serviceability shape:

- PCRTC raises vblank with `pcrtc_pending=1` and PMC PCRTC pending set.
- The guest clears PCRTC through `pcrtc_write`, producing a latest wait state
  of `pcrtc/intr-clear`.
- Native services vector `0x30` before PFIFO stream-idle while that latest
  wait state remains `pcrtc/intr-clear`.

The existing browser `XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM` branch
is too early as implemented. It is default-off and already plumbed through the
browser fixture path, so the patch should reuse that opt-in but revise its
semantics from "raise as soon as entry-ready" to "raise exactly once at the
verified PFIFO final-window boundary."

## Patch Plan

1. Keep the mode default-off and reuse
   `XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM`.
2. Stop `nv2a_vga_gfx_update()` from raising immediately on entry-ready when
   the deterministic PCRTC prestream mode is enabled. In that mode, regular
   browser vblank remains suppressed pre-stream until the PFIFO final-window
   trigger.
3. Add an internal helper in `nv2a.c`, exported through `nv2a_int.h`, for PFIFO
   to request a deterministic pre-stream PCRTC vblank raise.
4. Call that helper from `pfifo_run_pusher()` after the final method has been
   processed but before committing the last `DMA_GET` and before
   `pfifo_boot_trace_stream_idle_transition()`.
5. The helper raises only once and only if all gate predicates pass. On pass it
   performs the real PCRTC state mutation:
   - capture IRQ state,
   - set `d->pcrtc.pending_interrupts |= NV_PCRTC_INTR_0_VBLANK`,
   - reset raster,
   - call `nv2a_update_irq(d)`,
   - emit the existing `nv2a=irq-source source=pcrtc op=vblank-raise` marker.
6. Add a compact gate marker, for example
   `BOOT_MARK b6 nv2a=pcrtc-prestream-gate`, with action, reason, DMA state,
   PCRTC state, PFIFO/PGRAPH pending state, and trigger source.

## Gate Predicates

| Predicate | Source state | Failure reason |
| --- | --- | --- |
| Mode enabled | `XEMU_BROWSER_BOOT_DETERMINISTIC_PCRTC_PRESTREAM` fixture/env | `deterministic-prestream-disabled` |
| Dashboard observed | `xemu_xbe_boot_trace_dashboard_observed()` | `dashboard-not-observed` |
| Entry ready | `xemu_xbe_boot_trace_entry_ready()` | `entry-not-ready` |
| Pre stream-idle | `!xemu_xbe_boot_trace_pfifo_stream_idle_transition_observed()` | `stream-idle-observed` |
| PCRTC vblank enabled | `d->pcrtc.enabled_interrupts & NV_PCRTC_INTR_0_VBLANK` | `pcrtc-vblank-disabled` |
| PCRTC not already pending | `!(d->pcrtc.pending_interrupts & NV_PCRTC_INTR_0_VBLANK)` | `pcrtc-vblank-pending` |
| Single raise | static raise count is zero | `deterministic-prestream-limit` |
| Final PFIFO word | `dma_get_after == dma_put`, `dma_get_before != dma_get_after`, `dma_put - dma_get_before == 4` | `not-final-pfifo-word` |
| Final word processed | `available == 1`, `processed == 1` | `not-single-final-method` |
| PFIFO state stable | FIFO access true, no halt, no kick regression | `pfifo-not-stable` |
| PGRAPH not blocked | no waiting flip/nop/context switch | `pgraph-waiting` |

## Acceptance Matrix

| Check | Required outcome |
| --- | --- |
| Build | WASM build completes through the Podman path. |
| Browser runtime evidence | Browser runtime helper passes. |
| B4 display capture | Display capture helper passes. |
| Dashboard evidence | read/load/entry-ready/section-map pass. |
| PCRTC gate | Exactly one `nv2a=pcrtc-prestream-gate action=allow` before PFIFO stream-idle. |
| PCRTC IRQ source | A real `nv2a=irq-source source=pcrtc op=vblank-raise` appears before PFIFO stream-idle. |
| Guest clear | A later `nv2a=irq-source source=pcrtc op=intr-clear` appears before PFIFO stream-idle. |
| Vector service | Browser reports vector `0x30` service with latest wait source `pcrtc` and op `intr-clear` before PFIFO stream-idle, or the log explicitly proves why this still cannot happen. |
| Stable boundary preservation | PFIFO stream-idle, real IRET, and the `0x80030e84->0x80030f31` post-service watch edge remain present. |
| Tick movement | First watched read of `0x0003a890` moves above 0 ticks, or the same run proves the missing sub-field that blocked movement. |
| Strict B6 | `dashboard=xbe-executed` remains the required success marker; diagnostics do not satisfy B6 by themselves. |

## Failure Criteria

Reject the patch branch, do not tune it repeatedly, if the first runtime shows
any of these:

- Dashboard read/load/entry-ready regresses.
- B4 display capture regresses.
- No pre-stream PCRTC allow marker appears and the helper only reports
  `not-final-pfifo-word`.
- PCRTC raises but the guest never clears it before stream-idle.
- Vector `0x30`, real IRET, or post-service watch edge disappears as in the
  negative deterministic-PCRTC v2 branch.
- The run only reconfirms `missing-xbe-executed-marker` without changing or
  explaining `browser_pre_stream_vector_service_state`.

## Progress-Method Critique

This plan is still connected to strict dashboard execution because it targets
the missing pre-stream interrupt-serviceable state, not a looser display or
timer metric. It avoids broad PCRTC normal mode, host-pump count increases, PIT
bridges, and precommit timer reruns.

The process should now move from planning to one scoped code patch after the
required loop check. More static critique without a patch would slow progress.

## Decision

Continue only after the required sub-agent loop check for this static plan.

## Next step

Run the bounded sub-agent loop check with a `Progress-Method Critique`. If it
returns `continue`, implement the scoped default-off PFIFO final-window PCRTC
availability gate.
