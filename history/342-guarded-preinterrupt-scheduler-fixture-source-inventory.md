# Guarded Preinterrupt Scheduler Fixture Source Inventory

## Purpose

- One new fact this run was supposed to produce: the fixture source for the
  guarded preinterrupt scheduler runtime retry.

## Command(s)

```sh
rg -n "REAL_FIXTURE|FLASH|HDD|BOOTROM|xbox_hdd|fixture" scripts
env | rg "XEMU|FLASH|HDD|BOOTROM|FIXTURE|B3"
sed -n '1304,1320p' scripts/xbox-boot-evidence-report.sh
test -s '/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin'
test -s '/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2'
test -s '/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin'
test -s /tmp/xemu-b6-eeprom.bin
test -s '/home/sammy/.local/share/xemu/xemu/eeprom.bin'
mkdir -p build-real-b3-matrix/fixture-source-inventory-v1
XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin' \
XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin' \
XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin \
XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2' \
XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 \
scripts/xbox-real-fixtures-ready.sh \
> build-real-b3-matrix/fixture-source-inventory-v1/real-fixture-ready.log
```

## Inputs And Artifacts

- Baseline native log: `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Baseline browser log: `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`
- Output directory/log:
  `build-real-b3-matrix/fixture-source-inventory-v1/real-fixture-ready.log`
- Fixture assumptions: the existing evidence-report script records local
  machine paths for the private fixture assets; this inventory validates only
  presence, non-empty size, and fixture-readiness metadata.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  `guarded_preinterrupt_scheduler_fixture_source`.

## Findings

- Result: `guarded_preinterrupt_scheduler_fixture_source=env-paths-present`.
- Important marker/comparator lines:
  `REAL_FIXTURE_READY item=flash status=present source=env bytes=1048576`;
  `REAL_FIXTURE_READY item=hdd status=present source=env bytes=39714816`;
  `REAL_FIXTURE_READY item=mcpx status=present source=env bytes=512`;
  `REAL_FIXTURE_READY item=eeprom status=present source=env bytes=256`;
  `REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=0`.
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not
  applicable; no emulator run occurred.

## Decision

- Status: current
- Why: fixture sources are restored as explicit environment paths, so the prior
  preflight failure is explained and should not recur if the same exports are
  used.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: history 341 required fixture-source inventory before
  any runtime retry.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: history 341 said fixture discovery
  is acceptable only as a prerequisite restoration for the already-approved
  single runtime, not as a broader diagnostic branch.
- If yes, process adjustment for next 2-3 turns: run the required loop check
  before the runtime retry; if approved, retry the single guarded runtime once
  with these explicit fixture exports.

## Next Step

- Narrow follow-up: run the required loop check with progress-method critique
  before any runtime retry.
