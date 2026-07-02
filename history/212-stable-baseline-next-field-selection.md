# 212. Stable Baseline Next Field Selection

## Purpose

Perform the static stable-baseline reselection required by `history/211-stable-baseline-reselection-loop-check.md`. The goal was to choose exactly one next non-repeating field from existing evidence, without running a runtime or changing code.

## Commands

```sh
sed -n '1,140p' goal.md
rg -n -m 40 'high-alias|phys_match=no|xbe-exec-section-miss|xbe-exec-probe|xbe-executed|strict execution|section-miss' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
rg -n -m 60 'pre-service|tick ownership|first_watch_read|0-vs-136|high-alias|phys-mismatch|phys_match|section-miss|DMA_PUT|marker coverage' history goal.md
rg -n -m 40 'high-alias|phys_match|exec-section|exec_probe|xemu_xbe_pc_overlaps_loaded_image|xemu_xbe_phys_match_status|image_pc' xemu-xbe.c scripts -g '*.c' -g '*.py' -g '*.sh'
sed -n '140,340p' goal.md
sed -n '1,130p' history/63-main-menu-go-loop-check.md
sed -n '1,180p' history/116-pre-first-read-scheduler-ownership-inspection.md
sed -n '1,130p' history/136-pre-first-read-tcg-ordering-audit.md
sed -n '1,140p' history/118-emulation-thread-checkpoint-site-inspection.md
sed -n '1,130p' history/119-emulation-thread-checkpoint-site-loop-check.md
sed -n '1,130p' history/139-pre-first-read-micro-scheduler-loop-check.md
sed -n '1,120p' history/149-pre-first-read-micro-scheduler-activation-loop-check.md
sed -n '1,130p' history/180-before-interrupt-quarantine-runtime-restored-boundary.md
```

## Inputs and Artifacts

- Current goal:
  `goal.md`
- Stable browser CPU-flow baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Relevant history:
  `history/63-main-menu-go-loop-check.md`
  `history/116-pre-first-read-scheduler-ownership-inspection.md`
  `history/118-emulation-thread-checkpoint-site-inspection.md`
  `history/119-emulation-thread-checkpoint-site-loop-check.md`
  `history/136-pre-first-read-tcg-ordering-audit.md`
  `history/139-pre-first-read-micro-scheduler-loop-check.md`
  `history/149-pre-first-read-micro-scheduler-activation-loop-check.md`
  `history/180-before-interrupt-quarantine-runtime-restored-boundary.md`

## Candidate Fields

### Candidate A: strict execution high-alias classification

This is already heavily answered.

The stable baseline has an early strict section miss:

```text
dashboard=xbe-exec-section-miss reason=high-alias-phys-mismatch
```

It also has detector proof for the direct entry code:

```text
dashboard=xbe-executed-detector-proof result=pass subject=entry guest_pc=0x00017d60 ... phys_match=yes
```

Then the later execution probes repeatedly show high-alias paths with `phys_match=no`, `code_hash_match=no`, and no strict `dashboard=xbe-executed` marker. Goal/history already treat this as known: the strict detector is valid, and the browser is executing high-alias/kernel paths rather than the direct loaded-image mapping.

Reclassifying this path would mostly reconfirm `missing-xbe-executed-marker` and `high-alias-phys-mismatch`. It does not by itself change pre-service timing or make strict dashboard execution real.

### Candidate B: pre-service tick ownership

This remains the front-most actionable field.

Known state:

- native first watched read reaches 136 ticks;
- browser first watched read remains 0 ticks;
- broad host pump counts, pump placement, deterministic warmups, exact-PC IRQ defer, after-TB TCG pump predicate tuning, PFIFO-window/pusher/scheduler rediscovery, DMA_PUT marker coverage, and before-interrupt micro-scheduler activation are all negative or quarantined.

The surviving design direction is the M1 plan from `goal.md` and `history/63`: an opt-in deterministic browser boot mode or compact emulation-thread timeline that owns boot-critical timer/PFIFO/IRQ/CPU ordering before the first watched read, without weakening strict B6.

The nearest useful field is:

```text
browser_first_watch_read_ticks
```

The implementation constraint is now sharper than earlier attempts:

- no host-pump count tuning;
- no marker-only runtime;
- no PFIFO rediscovery;
- no exact-PC IRQ defer;
- no before-interrupt hook activation;
- preserve the stable ready-edge host4 post-service edge as the runtime guard.

## Decision

Select Candidate B.

The next non-repeating field is:

```text
browser_first_watch_read_ticks
```

The next code/design slice should be a compact deterministic pre-first-read scheduler/timeline that is opt-in, emulation-thread-owned, and explicitly excludes the quarantined before-interrupt hook. It should target `browser_first_watch_read_ticks > 1` while preserving the stable `0x80030e84->0x80030f31` post-service edge and strict B6 semantics.

## Next Step

Run the required loop check before inspecting or changing code for the deterministic pre-first-read scheduler/timeline.
