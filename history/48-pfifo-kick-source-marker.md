# PFIFO Kick Source Marker

## Purpose

- One new fact this run was supposed to produce: make the next focused browser
  runtime identify PFIFO kick provenance through
  `kick_sources_before_first_opportunity` and
  `first_kick_after_last_opportunity_source`, instead of reporting the current
  untagged `none` source.

## Command(s)

```sh
bash -n scripts/xbox-b6-current-boundary.sh scripts/xbox-pfifo-scheduler-state-classify-selftest.sh
python3 -m py_compile scripts/xbox-pfifo-scheduler-state-classify.py
scripts/xbox-pfifo-scheduler-state-classify-selftest.sh
scripts/xbox-pfifo-scheduler-state-classify.py --browser-log build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log
git diff --check -- AGENTS.md goal.md hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/user.c hw/xbox/nv2a/nv2a.c hw/xbox/nv2a/pgraph/pgraph.c hw/xbox/nv2a/pgraph/gl/surface.c hw/xbox/nv2a/pgraph/gl/display.c hw/xbox/nv2a/pgraph/vk/surface.c hw/xbox/nv2a/pgraph/vk/renderer.c hw/xbox/nv2a/pgraph/pgraph.h scripts/xbox-pfifo-scheduler-state-classify.py scripts/xbox-pfifo-scheduler-state-classify-selftest.sh scripts/xbox-b6-current-boundary.sh
PATH=/tmp/xemu-podman-wrapper:$PATH XEMU_WASM_SKIP_IMAGE_BUILD=1 XEMU_WASM_BUILD_DIR=build-wasm-pic XEMU_WASM_JOBS=4 scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Baseline native log:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-scheduler-v1/browser-runtime.log`
- Output directory/log: no new runtime log; this was a source-marker and helper
  update with wasm compile proof in `build-wasm-pic`.
- Fixture assumptions: no private fixture contents were read for the static
  checks or compile proof.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `kick_sources_before_first_opportunity`,
  `first_kick_after_last_opportunity_source`.

## Findings

- Result: pass.
- Important marker/comparator lines:
  - Existing scheduler artifact still reports
    `PFIFO_SCHEDULER_STATE_CLASSIFY result=pass
    divergence=no-pfifo-scheduler-event-before-first-opportunity`.
  - Existing artifact has `kick_sources_before_first_opportunity=none`,
    `first_kick_after_last_opportunity_line=1385`,
    `first_kick_after_last_opportunity_source=none`, and
    `first_kick_after_last_opportunity_delta=143`.
  - New code tags direct PFIFO wake call sites through
    `pfifo_kick_with_source(...)`; the old wrapper remains as
    `source=unspecified`.
  - The reducer and boundary helper now surface
    `last_scheduler_before_first_opportunity_kick_source`,
    `first_scheduler_after_last_opportunity_kick_source`,
    `kick_sources_before_first_opportunity`,
    `first_kick_after_last_opportunity_source`, and
    `first_kick_after_last_opportunity_delta`.
  - The wasm compile proof rebuilt and linked `qemu-system-i386.js`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress?
  Not tested by a runtime in this entry; no evidence contract was weakened.

## Decision

- Status: current
- Why: the next focused runtime can now answer the kick-source provenance
  question instead of repeating the already answered scheduler/pusher boundary.
- Independent critique used: yes
- If yes, critique decision: continue
- If yes, critique summary: history 47 said this is the non-looping next slice:
  inspect PFIFO kick call sites, add the smallest source marker, then rerun only
  the focused gate-split runtime.

## Next Step

- Narrow follow-up: run the required sub-agent loop check for this history entry,
  then rebuild/run the focused ready-edge host4 browser runtime only if the
  critique still says `first_kick_after_last_opportunity_source` is the right
  next field.
