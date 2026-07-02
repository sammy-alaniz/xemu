# PIT Bridge Quarantine Build

## Purpose

- One new fact this run was supposed to produce: `pit_bridge_branch_quarantined_build_status`.

## Command(s)

```sh
rg -n "PIT_PRE_STREAM|pit_pre_stream|pit-prestream|browser-pit-prestream-bridge|PitPreStream|browser_boot_pit_pre_stream" \
  ui/xemu-headless.c xemu-xbe.c \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  browser/xbox-boot/main.js browser/xbox-boot/worker.js

git diff --check -- \
  ui/xemu-headless.c xemu-xbe.c \
  scripts/xbox-browser-runtime-smoke.sh \
  scripts/xbox-browser-runtime-firefox-bidi.mjs \
  browser/xbox-boot/main.js browser/xbox-boot/worker.js

bash -n scripts/xbox-browser-runtime-smoke.sh

node --check scripts/xbox-browser-runtime-firefox-bidi.mjs
node --check browser/xbox-boot/main.js
node --check browser/xbox-boot/worker.js

PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs And Artifacts

- Touched source files:
  - `ui/xemu-headless.c`
  - `xemu-xbe.c`
- Touched browser/runtime plumbing files:
  - `scripts/xbox-browser-runtime-smoke.sh`
  - `scripts/xbox-browser-runtime-firefox-bidi.mjs`
  - `browser/xbox-boot/main.js`
  - `browser/xbox-boot/worker.js`
- Build artifact: `build-wasm-pic/qemu-system-i386.js`
- Fixture assumptions: no browser runtime was run; this is quarantine cleanup only.

## Expected Field(s)

- Loop-guard field(s) this run could change or explain:
  - `pit_bridge_branch_quarantined_build_status`

## Findings

- Result: `pit_bridge_branch_quarantined_build_status=pass`.
- Removed the live PIT pre-stream bridge option path from:
  - browser trace option specs,
  - worker fixture writer specs,
  - Firefox BiDi trace option/env summary,
  - browser runtime smoke trace option/env summary and final env handoff,
  - C-side browser-headless timer pump warmup branch,
  - C-side browser diagnostic source classifier.
- `rg` found no remaining live PIT bridge identifiers in the touched source/plumbing files.
- Static checks passed:
  - `git diff --check`
  - `bash -n scripts/xbox-browser-runtime-smoke.sh`
  - `node --check scripts/xbox-browser-runtime-firefox-bidi.mjs`
  - `node --check browser/xbox-boot/main.js`
  - `node --check browser/xbox-boot/worker.js`
- Podman-backed WASM build passed:
  - compiled `ui_xemu-headless.c.o`
  - compiled `xemu-xbe.c.o`
  - linked `qemu-system-i386.js`
- Did B4/B5/read/load/entry-ready/section-map/stream-idle/IRET regress? Not applicable; no runtime was run by design.

## Decision

- Status: current
- Why: the failed PIT bridge branch is quarantined at source/plumbing level and the build still succeeds. The stable ready-edge host4 baseline remains the runtime reference; no new browser runtime has been promoted.
- Independent critique used: yes
- If yes, critique decision: revise
- If yes, critique summary: `history/247-pit-bridge-quarantine-loop-check.md` required code cleanup/quarantine, forbidding more PIT bridge runtime or limit tuning.
- Loop-check progress-method critique included: yes
- If yes, progress-method critique summary: the prior loop check said the method is useful only if it exits failed timer-placement branches promptly.
- If yes, process adjustment for next 2-3 turns: select one static stable-baseline field before any runtime; do not start from the quarantined bridge artifact.

## Next Step

- Narrow follow-up: run the required post-history loop check with progress-method critique, then perform one static stable-baseline field selection before any new code or runtime.
