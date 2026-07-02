# 326 - pcrtc final-window BQL build

## Purpose

- One new fact this verification was supposed to produce: whether
  `pcrtc_final_window_irq_delivery_ownership` is build-safe after the PFIFO
  lock release, BQL acquire, PCRTC raise, BQL release, and PFIFO re-lock
  sequence.

## Command(s)

```sh
git diff --check

git diff -- hw/xbox/nv2a/pfifo.c | sed -n '1,180p'

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: no runtime fixtures used; Podman build used existing
  local WASM build image and skipped image rebuild.

## Expected Field(s)

- Loop-guard field(s) this verification could change or explain:
  `pcrtc_final_window_irq_delivery_ownership_build_safe`

## Findings

- Result: pass.
- Important marker/comparator lines:
  - `git diff --check` passed.
  - The diff inspection confirmed the ownership patch is limited to
    `hw/xbox/nv2a/pfifo.c` call-site ownership around the already-proven
    final-window candidate.
  - Podman WASM build passed and recompiled
    `hw_xbox_nv2a_pfifo.c.o`, then linked `qemu-system-i386.js`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not applicable; this was build/static verification only.

## Decision

- Status: current
- Why:
  The ownership patch is syntactically valid and build-safe in the browser
  target. No runtime has been run yet, so the next step must be loop-checked
  before deciding whether to test `browser_pre_stream_vector_service_state`.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary:
  `history/325-pcrtc-final-window-bql-patch-loop-check.md` approved exactly
  this build/static verification and no runtime before another loop check.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary:
  The prior critique said this is still on the causal path to strict dashboard
  execution and that the process is helping by avoiding broad PCRTC/PFIFO/timer
  reruns.
- If yes, process adjustment for next 2-3 turns:
  Continue allowing only actions that verify or preserve
  `pcrtc_final_window_irq_delivery_ownership` until this build result is
  loop-checked.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique.
  If approved, the next runtime must test only whether the BQL-safe
  final-window PCRTC IRQ changes `browser_pre_stream_vector_service_state`
  without regressing the existing B4/B5/read/load/entry-ready evidence.
