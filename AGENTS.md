# Repository Agent Notes

## Xbox Browser Boot Work

Primary reference: `xbox-browser-boot-plan.md`.

When working on the browser/WebAssembly Xbox boot effort, use the plan's boot ladder and phase ordering. Do not skip directly to graphics, audio, networking, or a polished browser UI before the headless boot path is proven.

Boot milestones:

- B0: process starts and constructs an Xbox machine.
- B1: firmware memory loads and CPU execution begins.
- B2: core Xbox devices initialize or show register activity.
- B3: storage boot path is active through real HDD/block reads.
- B4: boot animation or dashboard reaches a visible display path.
- B5: browser host is usable for config, persistence, start/stop, and logs.

Preferred first implementation slice:

1. Add gated boot markers and a controlled timeout/instruction budget.
2. Add a native headless/null boot harness.
3. Remove accidental SDL dependency from `hw/xbox/nv2a/pgraph/null/meson.build`.
4. Add a boot smoke script that extracts B0/B1/B2/B3 from logs.
5. Start the reduced wasm build profile only after native headless evidence exists.

Implementation constraints:

- Keep proprietary Xbox assets local and untracked.
- Standard local fixture directories are `fixtures/` and `xemu-fixtures/`; the real B3 runner auto-discovers `flash.bin`, `xbox_hdd.img`, optional `mcpx.bin`, optional `eeprom.bin`, and optional `dvd.iso` there, or from `XEMU_REAL_B3_FIXTURE_DIR`.
- Validate required flash and HDD fixture files as present and non-empty before real B3 runs.
- Validate MCPX boot ROM size as 512 bytes when used.
- Validate EEPROM size as 256 bytes.
- The first wasm target should be `i386-softmmu` with `--enable-tcg-interpreter`.
- Use the null renderer first.
- Keep audio and networking disabled for the initial browser boot path.
- Avoid desktop UI, SDL, OpenGL, Vulkan, ImGui, ImPlot, libpcap, and libsamplerate dependencies in the reduced wasm boot target.
- Browser pthread runs require a cross-origin-isolated context with COOP/COEP headers and `SharedArrayBuffer`.

Verification expectations:

- Every browser-boot task should have concrete pass/fail evidence.
- Use `scripts/xbox-browser-boot-verify-synthetic.sh` as the preferred no-private-assets regression gate before real fixture B3 work.
- Use `scripts/xbox-boot-next-step.sh` to get the current machine-readable next command from evidence.
- Use `scripts/xbox-fixture-privacy-check.sh` to verify standard private fixture paths are ignored and known fixture files are not tracked.
- Use `scripts/xbox-real-fixtures-ready.sh` for a non-emulating readiness report before preflight; set `XEMU_REAL_FIXTURE_READY_REQUIRE=1` when a missing or invalid fixture should fail the command.
- Use `scripts/xbox-real-fixture-manifest.sh` to generate a no-emulation handoff artifact with readiness and git privacy evidence before running real B3.
- Use `XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1 scripts/xbox-real-fixtures-ready.sh` only for isolated negative tests that must ignore repo-local `fixtures/` and `xemu-fixtures/` directories.
- Use `XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh` to validate real fixture discovery/sizes before running the full real B3 matrix. The matrix writes `build-real-b3-matrix/real-fixture-manifest.log`, `build-real-b3-matrix/real-fixture-manifest/real-fixture-manifest.md`, and `build-real-b3-matrix/real-fixture-ready.log`; evidence summary and next-step helpers use real B3 outputs when present.
- A full real B3 pass must include native/wasm marker comparison, real browser-block reads, and the browser selected-assets runtime smoke with a B3 marker plus config persistence evidence.
- Use `scripts/xbox-real-b3-evidence-check.sh <log>` to validate real B3 matrix evidence format.
- B4 is not proven by a marker alone; require a B4 marker plus `BROWSER_DISPLAY_CAPTURE result=pass ... nonempty=yes ...`.
- Use `scripts/xbox-display-capture-evidence-check.sh <log>` to validate B4 display capture evidence format.
- B5 is not proven by page load alone; require real selected-assets browser smoke with capabilities, artifacts, asset validation, config persistence, and B3 evidence.
- Use `scripts/xbox-browser-runtime-evidence-check.sh <log>` to validate B5 real browser runtime evidence format.
- Use `scripts/xbox-boot-completion-audit.sh` as the final diagnostic completion gate; it must fail until synthetic prerequisites and real B3/B4/B5 evidence all pass.
- Prefer logs or trace events over manual visual inspection until B4.
- Emit deterministic markers shaped like `BOOT_MARK ...` and a final `BOOT_SMOKE_RESULT ...` from smoke runs.
- Native headless boot smoke mode is enabled with `XEMU_HEADLESS_BOOT=1`; set `XEMU_BOOT_TRACE=1` for markers and optionally `XEMU_HEADLESS_BOOT_MS=<milliseconds>` for the timeout.
- Compare native headless and wasm marker sequences before investigating browser-only behavior.
- Measure TCI speed before investing heavily in renderer or product work.

## How To Continue On Another Machine

1. Check out this branch and install the same normal xemu build prerequisites plus Docker.
2. Do not commit proprietary Xbox assets. Put legally obtained local fixtures in `fixtures/` or `xemu-fixtures/`:
   - Required: `flash.bin`, `xbox_hdd.img`
   - Optional: `mcpx.bin` exactly 512 bytes, `eeprom.bin` exactly 256 bytes, `dvd.iso`
3. Run `scripts/xbox-fixture-privacy-check.sh` and confirm it reports fixture directories as ignored and no fixture files as tracked.
4. Run `scripts/xbox-real-fixtures-ready.sh`. Continue only after it reports `REAL_FIXTURE_READY_RESULT result=pass`.
5. Run `XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh` to validate discovery, sizes, privacy, and manifest output without doing the full real boot matrix.
6. Run `scripts/xbox-real-b3-matrix.sh` for real B3 evidence.
7. Run `scripts/xbox-boot-evidence-report.sh` and `scripts/xbox-boot-next-step.sh` after each meaningful run. The generated `xbox-browser-boot-status.md` should always explain the current state and next command.
8. Do not move to renderer/product polish until `scripts/xbox-real-b3-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log` passes.
9. After B3 passes, pursue B4 by adding a real display-path marker plus non-empty browser display capture evidence, then validate with `scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log`.
10. After B4 passes, pursue B5 browser usability and validate with `scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log`.
11. The final completion gate is `scripts/xbox-boot-completion-audit.sh`; it must fail until synthetic prerequisites and real B3/B4/B5 evidence all pass.

For iOS app work in this workspace, do not use the simulator.
