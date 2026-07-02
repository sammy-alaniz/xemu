# Strict Exec Causality Static

## Purpose

- One new fact this run was supposed to produce: `strict_exec_failure_depends_on_pre_service_tick_gap`.

## Command(s)

```sh
rg -n "dashboard=xbe-exec-section-miss|dashboard=xbe-executed|dashboard=xbe-exec-probe|dashboard=xbe-exec-transition|dashboard=xbe-exec-edge|dashboard=xbe-loaded|dashboard=xbe-entry-probe|memory-watch|main-loop=timers|pic=irq-ack|cpu=hard-irq-service|cpu=iret|pfifo=stream-idle" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "dashboard=xbe-exec-section-miss|dashboard=xbe-executed|dashboard=xbe-exec-probe|dashboard=xbe-exec-transition|dashboard=xbe-exec-edge|dashboard=xbe-loaded|dashboard=xbe-entry-probe|memory-watch|main-loop=timers|pic=irq-ack|cpu=hard-irq-service|cpu=iret|pfifo=stream-idle" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

rg -n "xemu_xbe_boot_trace_mark_executed|xemu_xbe_pc_overlaps_loaded_image|xemu_xbe_phys_match_status|xemu_xbe_image_pc_in_executable_section|exec_section_miss|high-alias|phys_match" xemu-xbe.c

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

scripts/xbox-post-service-edge-decision-compare.py \
  --log stable=build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "guest_pc=0x00017d60|image_pc=0x00017d60|direct phys_match=yes|dashboard=xbe-executed context" \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Source inspected: `xemu-xbe.c`
- Fixture assumptions: static inspection only; no code change and no runtime.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `strict_exec_failure_depends_on_pre_service_tick_gap`

## Findings

- Result: `strict_exec_failure_depends_on_pre_service_tick_gap=supported-current-best-causal-frontier-not-proven-exclusive`.
- The strict detector is not obviously rejecting a valid browser entry:
  - Browser emits `dashboard=xbe-executed-detector-proof ... result=pass ... subject=entry ... guest_pc=0x00017d60 ... address_mode=direct ... phys_match=yes`.
  - Native emits the same detector-proof shape at entry-ready.
- The first `dashboard=xbe-exec-section-miss reason=high-alias-phys-mismatch` is not by itself the active cause:
  - Browser first miss appears before entry-ready at line 1022.
  - Native first miss also appears before entry-ready at line 824, then native later succeeds at `dashboard=xbe-executed`.
  - Therefore early high-alias miss markers are normal diagnostic evidence while the low XBE page is not yet the current CPU target; they do not prove an independent strict-detector mapping bug.
- The actual strict success condition is direct low XBE execution:
  - `xemu_xbe_boot_trace_mark_executed()` accepts only overlap plus `phys_match=yes` plus executable section membership.
  - `xemu_xbe_boot_trace_observe_exec_transition()` calls `xemu_xbe_boot_trace_mark_executed(next_pc, 1, source)` before returning, so native succeeds when a post-TB next PC becomes `0x00017d60`.
  - Native has `BOOT_MARK b6 dashboard=xbe-executed ... guest_pc=0x00017d60 ... address_mode=direct phys_match=yes ... source=tcg-tb-post`.
  - The stable browser log has detector proof for `0x00017d60`, but no actual `dashboard=xbe-executed context=browser-runtime`.
- Stable browser preserves the useful post-service edge, so the tick arithmetic inside the watched block is not the failing arithmetic:
  - `POST_SERVICE_WATCH_EDGE_COMPARE result=pass divergence=pre-block-watch-value-mismatch`
  - native block delta: 1 tick
  - browser block delta: 1 tick
  - edge-decision classification: `useful-post-service-edge`
- The browser is already behind before entering that useful comparable path:
  - `PRE_SERVICE_TICK_GAP_COMPARE result=pass divergence=browser-first-watch-read-before-catchup`
  - native first watched read: 136 ticks at `0x80014f5f->0x80030e84`
  - browser first watched read: 0 ticks at `0x80014f32->0x80030e84`
  - first watched read delta: 136 ticks
- Native also spends time in high-alias mismatch paths after entry-ready before eventually reaching direct low entry. This makes high-alias mismatch a symptom of current CPU path, not an independent proof that the detector is wrong.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run.

## Decision

- Status: current
- Why: keep the strict B6 checker unchanged. The next work should not weaken `dashboard=xbe-executed`; it should explain why browser control flow reaches the preserved post-service edge with the watched word 136 ticks behind and then never reaches native's direct low-entry execution.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: `history/249-stable-field-selection-loop-check.md` requested this exact static causality decision before any new code.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said to choose between tick-gap work and strict-exec high-alias work; this inspection keeps the focus on tick-gap/control-flow and rejects checker weakening.
- If yes, process adjustment for next 2-3 turns: choose one code-inspection target that explains pre-service tick accumulation or post-service low-entry handoff from the stable baseline; do not add runtime probes first.

## Next Step

- Narrow follow-up: run the required post-history loop check. Ask whether the next static target should be timer/PIT pre-service accumulation, interrupt-service ordering, or post-service low-entry handoff.
