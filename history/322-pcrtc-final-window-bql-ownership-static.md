# 322 - pcrtc final-window BQL ownership static

## Purpose

- One new fact this static inspection was supposed to produce: where the
  final-window PCRTC IRQ should be delivered so `cpu_interrupt()` runs with
  valid BQL ownership.

## Command(s)

```sh
rg -n "bql_locked|cpu_interrupt|qemu_mutex_iothread|bql_|aio_bh|qemu_bh|bottom half|qemu_mutex_lock_iothread|qemu_mutex_unlock_iothread" system include hw/xbox hw/core accel target/i386 | head -n 200
rg -n "nv2a_update_irq|pcrtc-vblank|pcrtc_pre|deterministic_pcrtc|pcrtc.pending_interrupts|qemu_set_irq|pic|irq-line" hw/xbox/nv2a hw/xbox | head -n 240
sed -n '230,310p' system/cpus.c
sed -n '1,220p' hw/xbox/nv2a/nv2a.c
sed -n '180,420p' hw/xbox/nv2a/nv2a.c
sed -n '520,680p' hw/xbox/nv2a/pfifo.c
sed -n '1220,1295p' hw/xbox/nv2a/pfifo.c
sed -n '1310,1345p' hw/xbox/nv2a/nv2a.c
sed -n '1180,1230p' hw/xbox/nv2a/nv2a.c
rg -n "static void pfifo_run_pusher|void pfifo_run_pusher|qemu_mutex_lock\\(&d->pfifo.lock\\)|qemu_mutex_unlock\\(&d->pfifo.lock\\)" hw/xbox/nv2a/pfifo.c
sed -n '1120,1335p' hw/xbox/nv2a/pfifo.c
sed -n '1335,1435p' hw/xbox/nv2a/pfifo.c
sed -n '1,80p' hw/xbox/nv2a/pfifo.c
sed -n '560,610p' system/cpus.c
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  code inspection only; no runtime output
- Fixture assumptions: no fixtures used.

## Expected Field(s)

- Loop-guard field(s) this inspection could change or explain:
  `pcrtc_final_window_irq_delivery_ownership`

## Findings

- Result:
  `pcrtc_final_window_irq_delivery_ownership=pfifo-thread-without-bql`.
- Important marker/comparator lines:
  - `system/cpus.c` requires `bql_locked()` in `cpu_interrupt()`.
  - `nv2a_update_irq()` asserts/deasserts the PCI IRQ line; that path can reach
    `cpu_interrupt()` and therefore needs BQL held.
  - Regular PCRTC vblank delivery from `nv2a_graphic_update()` is already on a
    path that satisfies the BQL contract.
  - `pfifo_run_pusher()` runs under `d->pfifo.lock` from `pfifo_thread()`.
  - Existing PFIFO diagnostic timer-pump code explicitly drops
    `d->pfifo.lock`, takes BQL, performs interrupt-capable timer work, releases
    BQL, and re-locks `d->pfifo.lock` to avoid the normal
    BQL-to-PFIFO lock-order inversion.
  - The new final-window helper currently calls `nv2a_update_irq()` directly
    from inside the PFIFO pusher path, before the DMA_GET commit and while
    `d->pfifo.lock` is still held.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was static inspection only.

## Decision

- Status: current
- Why:
  The next narrow patch should preserve the exact final-window gate semantics
  and change only the ownership of the IRQ delivery. The most local pattern is
  the one already used in `pfifo.c`: for the one-shot final-window candidate,
  drop the PFIFO mutex before taking BQL, call the deterministic PCRTC helper,
  release BQL, then re-lock PFIFO.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/321-pcrtc-final-window-runtime-loop-check.md` approved code
  inspection first and code change only if the BQL-safe delivery path was clear.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The prior critique said the method is still connected to strict dashboard
  execution but must avoid runtime probing until BQL ownership is understood.
  This inspection answered that ownership question without rerunning emulation.
- If yes, process adjustment for next 2-3 turns:
  Do not tune PFIFO windows, pump counts, PCRTC modes, or timer limits. Only
  patch delivery ownership for the already-proven final-window gate.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  If approved, patch only the final-window PCRTC delivery ownership path and
  verify with build/static checks before any runtime.
