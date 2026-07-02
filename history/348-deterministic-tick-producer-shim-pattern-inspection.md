# Deterministic Tick Producer Shim Pattern Inspection

## Purpose

- One new fact this run was supposed to produce: the narrowest existing pattern
  for an opt-in browser-only deterministic tick producer strategy.

## Command(s)

```sh
rg -n "deterministic|compat|shim|write_phys|address_space_write|cpu_physical_memory_write|xemu_xbe_write|read_phys_u32|ldl_le_p|stl_le_p|phys" xemu-xbe.c xemu-xbe.h browser scripts ui accel hw | head -n 240
rg -n "BROWSER_BOOT_DETERMINISTIC|browser_boot_deterministic|deterministic" -S .
rg -n "memory_region|address_space|cpu_physical_memory|stl_le|ldl_le|write_phys|read_phys" xemu-xbe.c hw/xbox include/system include/exec system accel | head -n 260
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log: static command output in the Codex transcript
- Fixture assumptions: not relevant; this was static inspection only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `pre_first_read_tick_producer_strategy_decision`.

## Findings

- Result: existing code already has an opt-in browser deterministic boot
  framework through `XEMU_BROWSER_BOOT_DETERMINISTIC` and fixture files such as
  `browser_boot_deterministic.txt`.
- Existing deterministic wiring spans:
  - `browser/xbox-boot/main.js` and `browser/xbox-boot/worker.js` diagnostic
    fixture propagation;
  - `scripts/xbox-browser-runtime-smoke.sh` and
    `scripts/xbox-browser-runtime-firefox-bidi.mjs` env propagation and
    reporting;
  - `ui/xemu-headless.c` deterministic warmup and marker emission.
- There is no current deterministic tick-word producer shim. The existing
  deterministic PCRTC branch is historical negative evidence and should not be
  reused as the promotion path.
- Existing physical memory helpers are available: `stl_le_phys()` is used in
  Xbox device code, and `xemu-xbe.c` already reads the watched physical word via
  `xemu_xbe_read_phys_u32()`.
- A narrow patch target is therefore possible in `xemu-xbe.c`: add a
  browser-only, opt-in deterministic pre-first-read tick producer that writes
  physical `0x0003a890` to a configured tick count before the sampled
  `0x80014f32 -> 0x80030e84` edge, emits a marker, and does not set
  `executed_marked` or emit `dashboard=xbe-executed`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not
  applicable; no emulator run occurred.

## Decision

- Status: current
- Why: the implementation should use a new explicit deterministic tick-producer
  sub-knob rather than overloading existing timer pump modes or weakening strict
  B6 evidence.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history 347 approved a deterministic producer
  strategy only if it is opt-in, browser-only, deterministic, logged, and does
  not fake `dashboard=xbe-executed`.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: history 347 said the work is
  actionable now, but risks architectural drift if a shim silently masks
  emulation ordering.
- If yes, process adjustment for next 2-3 turns: patch only an explicit
  deterministic compatibility step, then build-check before any runtime.

## Next Step

- Narrow follow-up: run the required loop check before patching the deterministic
  tick producer shim.
