# 184. Restored Read-Complete Static Compare

## Purpose

Determine whether the restored artifact's
`missing-xbe-read-complete-marker` is artifact-specific checker/logging behavior
or a real regression from the stable browser baseline.

## Commands

```sh
ls -l \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log

rg -n "dashboard=xbe-read|dashboard=xbe-read-complete|dashboard=xbe-loaded|dashboard=xbe-executed|DASHBOARD_LOADED_EVIDENCE" \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log

sed -n '1,220p' scripts/xbox-dashboard-loaded-evidence-check.sh

rg -n "xbe-read-complete|read-complete|complete=yes|contiguous_bytes|image_size|missing-xbe-read" \
  scripts xemu-xbe.c

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log
scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n '^BOOT_MARK b6 dashboard=xbe-read |^BOOT_MARK b6 dashboard=xbe-read-complete |^BOOT_MARK b6 dashboard=xbe-entry-probe .*status=ready|^BOOT_MARK b6 dashboard=xbe-executed ' \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log \
  build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

sed -n '1,160p' history/152-pre-first-read-micro-scheduler-armed-runtime.md

rg -n "combined|xbe-read|read-complete|missing-xbe-read|missing-xbe-executed|xbox-dashboard-loaded-evidence-check" \
  history/152-pre-first-read-micro-scheduler-armed-runtime.md \
  history/180-before-interrupt-quarantine-runtime-restored-boundary.md \
  history/154-pre-first-read-gate-marker-build-pass.md \
  history/156-pre-first-read-gate-marker-runtime.md

rg -n "browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined|ready-edge-host4-v1-combined|combined.log|dashboard=xbe-read" \
  history goal.md AGENTS.md | head -120

rg -n "dashboard=xbe-read context=browser-runtime|xbox-dashboard-xbe-read-evidence|ide-read-log" \
  scripts history | head -160

scripts/xbox-combine-dashboard-xbe-read-evidence.sh \
  --hdd '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
  --log build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log \
  --out build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log \
  --require-context browser-runtime

scripts/xbox-dashboard-loaded-evidence-check.sh \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log

scripts/xbox-pre-service-tick-gap-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log

scripts/xbox-post-service-watch-edge-compare.py \
  --native-log build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  --browser-log build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log

rg -n '^BOOT_MARK b6 dashboard=xbe-read |^BOOT_MARK b6 dashboard=xbe-executed |DASHBOARD_LOADED_EVIDENCE' \
  build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log
```

## Inputs / Artifacts

- Restored raw log:
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime.log`
- Restored combined log:
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log`
- Stable combined baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Earlier armed raw log:
  `build-real-b3-matrix/browser-pre-first-read-micro-scheduler-armed-v1/browser-runtime.log`

## Loop-Guard Field

- `read_complete_absence_artifact_specific`

## Findings

The raw restored artifact's `missing-xbe-read-complete-marker` is
artifact-specific, not a new B6 blocker by itself.

- The raw restored log and the earlier armed raw log both stop read-progress at
  `contiguous_bytes=172032 image_size=175080` and fail the strict dashboard
  helper at `missing-xbe-read-complete-marker`.
- The stable baseline is a combined log. It includes a synthetic/audited FATX
  read proof line:
  `dashboard=xbe-read context=browser-runtime ... source=ide-read-log`.
- Running `scripts/xbox-combine-dashboard-xbe-read-evidence.sh` on the restored
  raw artifact produced
  `build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log`.
- The restored combined log now contains `dashboard=xbe-read` and the strict
  dashboard helper advances to
  `DASHBOARD_LOADED_EVIDENCE result=fail reason=missing-xbe-executed-marker`.

However, the restored artifact should not replace the stable front-most
baseline:

- `scripts/xbox-pre-service-tick-gap-compare.py` on the restored raw log fails
  with `divergence=missing-first-watch-read`.
- `scripts/xbox-post-service-watch-edge-compare.py` on the restored raw log
  fails with `divergence=missing-browser-pre-edge,browser-post-edge`.
- The stable ready-edge host4 combined baseline remains the sharper CPU-flow
  artifact because it preserves the first watched read and post-service watch
  edge needed to measure the 0/1 vs native 136 tick gap.

## Decision

The `missing-xbe-read-complete-marker` finding is resolved as a raw-log/combiner
artifact. The active B6 blocker remains strict browser dashboard execution and
the pre-service tick/post-service CPU-flow divergence, not read-complete.

Do not promote
`build-real-b3-matrix/browser-before-interrupt-quarantine-runtime-v1/browser-runtime-combined.log`
over the stable ready-edge host4 combined baseline as the front-most B6
diagnostic.

## Next Step

Run the required bounded loop check. Ask whether `goal.md` should be adjusted to
say the read-complete artifact is resolved after combining, while the stable
ready-edge host4 combined baseline remains the front-most CPU-flow baseline.
