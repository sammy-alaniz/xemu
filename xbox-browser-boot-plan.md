# Xbox Browser Boot Plan

This plan turns the browser port analysis into a boot-focused engineering path. The goal is not "playable xemu in a browser" at first. The first real win is proving that an Xbox machine can initialize, execute firmware, read the expected storage, and reach a dashboard boot signal under WebAssembly with the null renderer.

## Scope

Target outcome:

- Boot an original Xbox firmware/dashboard path in a browser-hosted WebAssembly build.
- Keep the first browser build headless or null-rendered.
- Add visible output only after CPU, storage, threading, and launch plumbing are proven.

Non-goals for the first boot:

- Full-speed gameplay.
- Network play.
- Browser-native audio.
- Full OpenGL renderer parity.
- Loading full HDD or DVD images into wasm memory.

Asset assumptions:

- The developer supplies legally obtained Xbox firmware, MCPX boot ROM, EEPROM, HDD, and optional DVD images.
- These files are local test fixtures and must not be checked into the repository.
- MCPX boot ROM must be 512 bytes when used.
- EEPROM must be 256 bytes.
- BIOS/flash image must be a valid Xbox BIOS image, with size accepted by `hw/xbox/xbox.c`.

## Boot Milestones

Use these boot levels to avoid vague progress claims.

| Level | Meaning | Required evidence |
| --- | --- | --- |
| B0 | Process starts and constructs an Xbox machine | Launch log shows `-machine xbox`, RAM size, BIOS path, EEPROM device, IDE drives, and `renderer=NULL`; process exits by a controlled timeout, not a crash |
| B1 | Firmware memory is loaded and CPU executes | Logs show BIOS and optional MCPX load succeeded, TCG/TCI instruction count increases, and execution moves past reset entry |
| B2 | Core Xbox devices are active | Logs or traces show SMC/SMBus, IDE, NV2A, APU, USB, and nvnet initialization or register access without fatal errors |
| B3 | Storage boot path is active | IDE/block logs show HDD sector reads from the expected dashboard partitions and no missing/invalid media errors |
| B4 | Dashboard or boot animation reaches display path | Canvas or framebuffer capture shows reproducible non-empty frames matching native reference captures |
| B5 | Browser run is usable | Browser page can configure assets, persist EEPROM/config, start/stop, and collect logs without devtools-only manual steps |

The first serious browser-port gate is B3, not B4. A null-renderer browser build that reaches B3 proves most non-graphics boot blockers have been cleared.

## Current Repo Anchors

Relevant files from the analysis and source inspection:

- `meson.build`: recognizes `emscripten` and `wasm32`; wasm host requires `--enable-tcg-interpreter`; several dependencies are still desktop-oriented.
- `configs/meson/emscripten.txt`: enables pthreads, Asyncify, `PROXY_TO_PTHREAD`, filesystem support, 2 GB memory, BigInt, and ES module output.
- `system/vl.c`: builds xemu's Xbox launch arguments, including `-machine xbox`, BIOS, EEPROM, HDD, DVD, and currently hardcoded `-display xemu`.
- `hw/xbox/xbox.c`: loads BIOS/MCPX ROM, initializes RAM, PCI, SMC, IDE, USB, nvnet, APU, ACI, and NV2A.
- `config_spec.yml`: exposes `display.renderer` values of `NULL`, `OPENGL`, and `VULKAN`, and file paths for boot ROM, flash ROM, EEPROM, HDD, and DVD.
- `hw/xbox/nv2a/pgraph/null/renderer.c`: existing null renderer.
- `hw/xbox/nv2a/pgraph/null/meson.build`: null renderer build rules must stay independent from SDL.
- `ui/meson.build`: desktop builds add xemu SDL/OpenGL/ImGui UI sources; browser-boot builds use the headless entrypoint and stubs.

## Phase 0: Native Baseline And Evidence

Goal: establish a known-good native boot reference and define the exact evidence that counts as progress.

| Task | Work | Verification |
| --- | --- | --- |
| 0.1 Define fixture layout | Create a local, untracked fixture directory for `mcpx.bin`, `flash.bin`, `eeprom.bin`, `xbox_hdd.img`, and optional `dvd.iso`. Document expected paths through environment variables such as `XEMU_MCPX`, `XEMU_FLASH`, `XEMU_EEPROM`, `XEMU_HDD`, and `XEMU_DVD`. | `test "$(wc -c < "$XEMU_MCPX")" -eq 512`; `test "$(wc -c < "$XEMU_EEPROM")" -eq 256`; BIOS size is accepted by a native xemu launch; fixture directory is ignored by git. |
| 0.2 Capture native boot logs | Run the current native desktop build with the same assets and a config that uses the null renderer if possible. Capture logs from process start through dashboard boot or first known boot failure. | Log includes created QEMU launch parameters, successful BIOS load, EEPROM device, IDE drives, Xbox device initialization, and the highest boot milestone reached. |
| 0.3 Add boot progress markers | Add temporary or gated log markers around `xbox_flash_init`, `xbox_memory_init`, `xbox_init_common`, `nv2a_init`, `mcpx_apu_init`, IDE drive creation, and first block reads. Prefer trace events or a `XEMU_BOOT_TRACE=1` gate. | A native run emits deterministic markers for B0-B3 without relying on a visible window. Markers are timestamped or instruction-counted enough to compare native and wasm runs. |
| 0.4 Define controlled exit | Add a boot-smoke timeout or instruction budget for automated runs, for example `--boot-smoke-ms=30000` or an internal test-only env var. | Native run exits with a distinct success/timeout code and writes a final line like `BOOT_SMOKE_RESULT level=B2 elapsed_ms=...`, rather than needing a manual close. |

Exit criteria:

- Native run reaches at least B3 with the target assets, or the native failure is understood and documented.
- There is a repeatable command or script that produces boot evidence without manual UI inspection.

## Phase 1: Native Headless/Null Boot Harness

Goal: separate "Xbox machine can boot" from "desktop xemu UI can run".

| Task | Work | Verification |
| --- | --- | --- |
| 1.1 Add a headless launch mode | Introduce a native boot harness that avoids `-display xemu`, SDL window creation, ImGui, and OpenGL context requirements. This can be a new `-display xemu-headless`, a `--headless-boot-smoke` mode, or a build option that maps the hardcoded display in `system/vl.c` to a no-window display for smoke tests. | Native command runs without opening a window. Logs still show `-machine xbox`, `smbus-storage`, HDD, DVD drive, and the Xbox device tree. |
| 1.2 Force the null renderer in headless mode | Set `g_config.display.renderer` to `CONFIG_DISPLAY_RENDERER_NULL` for the harness, or load a test config that does so before NV2A initialization. | Log includes `renderer=NULL` or `PGRAPH renderer: Null`; no OpenGL, Vulkan, shader cache, or SDL renderer initialization appears in the log. |
| 1.3 Remove accidental SDL dependency from null renderer | Change `hw/xbox/nv2a/pgraph/null/meson.build` so the null renderer does not add `sdl` unless another source in that target actually needs it. | Native and wasm Meson dependency graphs can include the null renderer without requiring SDL. A native build with SDL disabled gets past this target. |
| 1.4 Keep device threads observable | Add markers for thread creation and first loop iteration for QEMU main thread, NV2A PFIFO, MCPX APU frame thread, and voice workers. | Headless native run logs each expected thread or explicitly logs when a subsystem is disabled for the harness. |
| 1.5 Add a native boot smoke test script | Create a script target such as `scripts/xbox-boot-smoke.sh` that validates fixtures, runs the harness, stores logs, and extracts the highest boot level. | Script exits 0 for the expected boot level and nonzero for crashes, missing assets, invalid asset sizes, or regression below the expected boot level. |

Exit criteria:

- Native headless/null run reaches the same B-level as the desktop reference, ideally B3.
- The boot evidence is reproducible enough to compare against wasm runs.

## Phase 2: Reduced Wasm Build Profile

Goal: build the smallest wasm xemu that can construct and run the Xbox machine with TCI and null rendering.

| Task | Work | Verification |
| --- | --- | --- |
| 2.1 Add a browser boot build option | Add a Meson option such as `xemu_browser_boot` or `xemu_headless_boot` that excludes desktop UI sources and selects only the dependencies needed for headless Xbox boot. | `meson setup` for wasm shows the option enabled and does not require SDL, OpenGL, ImGui, ImPlot, Vulkan, libpcap, or libsamplerate for the headless target. |
| 2.2 Fix non-browser dependency assumptions | Make `libpcap`, `libsamplerate`, `epoxy`/OpenGL, and desktop GL platform checks conditional for the reduced wasm target. Keep stubs or disabled backends for network and audio. | Wasm configure gets past dependency discovery without host desktop libraries. Build logs show networking and audio output disabled or stubbed intentionally. |
| 2.3 Keep `i386-softmmu` and TCI explicit | Configure wasm with `--target-list=i386-softmmu` and `--enable-tcg-interpreter`. Do not hide the CPU performance risk. | Configure logs show host `wasm32`/`emscripten`, target `i386-softmmu`, `tcg_arch=tci`, and no native TCG backend. |
| 2.4 Produce wasm artifacts | Build the reduced target with `configs/meson/emscripten.txt`, preserving pthreads, filesystem, BigInt, and 2 GB memory settings unless measured evidence says otherwise. | Build outputs `.wasm` plus JS module artifacts. Artifact size, linker flags, and exported runtime methods are recorded in the build log. |
| 2.5 Confirm excluded source paths | Add a build-log check or CI smoke grep that proves desktop UI and GL renderer sources are not compiled for the reduced target. | Build log contains null renderer and Xbox hardware files; build log does not contain `ui/xemu.c`, OpenGL PGRAPH renderer files, Vulkan PGRAPH renderer files, or shader cache workers for this target. |

Exit criteria:

- A wasm binary/module can be built repeatedly from a clean tree.
- The wasm build contains enough Xbox hardware code for B0-B3, but excludes desktop display/audio/network complexity.

## Phase 3: Wasm Headless Runner

Goal: run the reduced wasm artifact outside the full browser UI first, with deterministic assets and logs.

| Task | Work | Verification |
| --- | --- | --- |
| 3.1 Create a JS smoke runner | Add a Node-compatible or browser-worker-compatible runner that mounts small fixtures into Emscripten FS and passes the same boot harness arguments as native. | Runner starts the wasm module, prints boot markers to stdout or a captured log buffer, and exits under the same controlled timeout. |
| 3.2 Mount BIOS and EEPROM through Emscripten FS | Load MCPX, flash, and EEPROM into paths that `system/vl.c` and `hw/xbox/xbox.c` can open normally. | Wasm log shows successful BIOS path, optional MCPX path, and EEPROM device. Invalid size tests fail with the same messages as native. |
| 3.3 Mount a minimal HDD path | For the first run, allow a small file-backed test image in MEMFS if it is enough to exercise IDE/block paths. Do not treat this as the final dashboard storage solution. | Wasm reaches B2 and shows IDE/block reads from the mounted file. Memory use stays below the configured wasm memory limit. |
| 3.4 Verify pthread requirements | Run in an environment that supports wasm threads. Confirm worker creation and shared memory behavior before chasing emulator bugs. | Logs show pthread worker startup. A missing SharedArrayBuffer or worker failure produces a clear capability error before emulation starts. |
| 3.5 Compare native and wasm boot markers | Diff native and wasm marker sequences through the highest common milestone. | Wasm reaches B0, then B1, then B2 in order. First divergence from native is captured with marker name, elapsed time, and recent log context. |
| 3.6 Measure TCI baseline speed | Count guest instructions, translated blocks, or boot markers per second for native TCI and wasm TCI. | Report includes native TCI rate, wasm TCI rate, and estimated time to dashboard. If B3 would take impractical time, stop before graphics work and revisit CPU strategy. |

Exit criteria:

- Wasm headless reaches at least B2.
- The first major divergence from native is known.
- TCI speed is measured, not guessed.

## Phase 4: Browser Host Shell

Goal: provide a repeatable browser environment for the headless wasm build.

| Task | Work | Verification |
| --- | --- | --- |
| 4.1 Add a local browser shell | Create a minimal HTML/JS host that loads the wasm ES module, runs it in a worker, captures logs, and exposes start/stop controls. | Browser page can start the same headless boot run as the JS smoke runner. Logs appear in-page and can be downloaded. |
| 4.2 Serve with isolation headers | Add a local dev server that sets COOP and COEP headers required for SharedArrayBuffer and pthreads. | Browser capability check reports `crossOriginIsolated=true`, `SharedArrayBuffer` available, wasm threads available, and BigInt available. |
| 4.3 Add asset pickers and validation | Add file pickers for MCPX, flash, EEPROM, HDD, and optional DVD. Validate size and required files before boot. | Bad MCPX/EEPROM sizes fail before wasm starts. Valid files are mounted under stable paths and shown in the launch log. |
| 4.4 Persist small mutable files | Store generated or edited EEPROM/config in IDBFS or OPFS. Keep user-provided BIOS/HDD/DVD external unless explicitly imported. | After page reload, EEPROM/config are restored and checksums or byte counts match the previous run. |
| 4.5 Add browser boot transcript export | Save logs, selected boot level, user-agent, capability checks, build hash, and artifact metadata in one downloadable text or JSON file. | A failed browser boot creates enough data to reproduce or compare against native/Node smoke runs. |

Exit criteria:

- Browser shell can run the reduced wasm target to the same B-level as the JS smoke runner.
- Browser capability and asset failures are explicit and actionable.

## Phase 5: Browser Storage For Real Boot

Goal: support random-access HDD and DVD image reads without loading full images into wasm memory.

| Task | Work | Verification |
| --- | --- | --- |
| 5.1 Design a browser block backend | Choose a synchronous-in-worker strategy for QEMU block access. Prefer OPFS SyncAccessHandle or a chunked file-access layer that preserves random reads and writes from the emulation thread. | Design note explains read/write semantics, locking, persistence, maximum image size, and how blocking C calls map to browser APIs. |
| 5.2 Implement HDD random reads | Add a block backend or Emscripten filesystem device that can serve random HDD sectors from browser storage without preloading the whole image. | A test reads random sector offsets and compares hashes against the same sectors read natively. Memory does not grow with total HDD image size. |
| 5.3 Implement required writes | Support EEPROM and HDD writes needed by the dashboard path, with flush semantics that survive browser reload. | Random write/readback tests pass. After browser reload, changed sectors and EEPROM bytes persist. |
| 5.4 Add optional DVD random reads | Add the same random-read strategy for DVD ISO/XISO if dashboard boot or game boot needs it. | Browser block test reads random DVD sectors and matches native hashes. Boot run logs DVD media as absent or present according to picker state. |
| 5.5 Run B3 browser boot | Use real dashboard-capable HDD assets with null rendering and no audio/network. | Browser log reaches B3: IDE reads come from the expected HDD image, dashboard boot path begins, and no full-image preload occurs. |

Current Phase 5 storage direction:

- `browser/xbox-boot/block-storage.mjs` is the browser-side random-access
  block helper. `BlobBlockDevice` reads byte ranges and sectors from a
  `Blob`/`File` with `slice().arrayBuffer()`, which keeps reads proportional
  to requested ranges instead of total image size.
- The browser main thread now leaves selected HDD/DVD files as `Blob`/`File`
  objects when posting work to the boot worker. The worker emits
  `BROWSER_BLOCK_PROBE result=pass ...` after deterministic sector reads from
  the block helper. It then prefers OPFS `createSyncAccessHandle()` backing and
  emits `BROWSER_BLOCK_BACKING result=pass ... backend=opfs-sync`; if OPFS is
  unavailable it emits `BROWSER_BLOCK_MATERIALIZE ...` and
  `BROWSER_BLOCK_BACKING ... backend=memory` for the explicit fallback.
- The QEMU raw file driver has a browser-boot-only Emscripten branch for
  `/xemu-browser-block/...` paths. It opens those paths through synchronous
  `Module.xemuBrowserBlock*` callbacks, reports length without `fstat()`, and
  forwards read/write/flush/close calls to the worker-owned registry through
  `MAIN_THREAD_EM_ASM_*`, so calls from QEMU pthreads are proxied to the main
  wasm runtime thread. Successful C-side open/read/write operations emit
  `BOOT_MARK b3 browser_block=...`.
- `OverlayBlockDevice` layers sparse writes over a readable base device in
  fixed-size chunks. This is the first persistence shape for dashboard writes:
  read unchanged bytes from the base image, track dirty chunks separately, and
  flush those chunks to durable browser storage.
- `SyncMemoryBlockDevice` is the worker-safe memory fallback used by the
  synchronous C callback path. It tracks dirty block chunks during C-side writes
  and emits `BROWSER_BLOCK_SNAPSHOT result=pass ...` on flush with a JSON/base64
  overlay snapshot. The worker loads any matching IndexedDB snapshot before
  exposing a memory-backed block and emits `BROWSER_BLOCK_SNAPSHOT_LOAD ...`;
  it then asynchronously stores new snapshots in IndexedDB and emits
  `BROWSER_BLOCK_SNAPSHOT_PERSIST result=pass ...` when the durable handoff
  completes. OPFS-backed blocks continue to flush through
  `SyncAccessHandle.flush()`.
- The QEMU integration now services C-side read/write requests from a
  worker-owned storage object. This is still not B3 proof until a browser boot
  run with real assets emits the browser block read markers.

Exit criteria:

- Browser run reaches B3 with real storage.
- Storage memory use and persistence behavior are acceptable.

## Phase 6: Minimal Browser Display Path

Goal: make boot progress visible after headless browser boot is proven.

| Task | Work | Verification |
| --- | --- | --- |
| 6.1 Add a synthetic framebuffer test | Before Xbox rendering, add a controlled test pattern path from wasm memory to browser canvas. | Browser canvas displays a deterministic pattern; canvas pixel hash is stable and `scripts/xbox-browser-display-capture-smoke.sh` emits validated synthetic display evidence. |
| 6.2 Add a minimal scanout path | Create a browser framebuffer renderer or scanout bridge that can copy a guest-visible surface to JS without using the desktop OpenGL 4 renderer. | Native and browser test patterns from the same guest memory produce matching screenshots. |
| 6.3 Capture native reference frames | Capture known native frames for the boot animation/dashboard using the existing desktop renderer. | Reference images are generated from the same assets and build hash, then stored outside proprietary asset paths. |
| 6.4 Attempt visible boot | Run the browser build with storage and minimal scanout enabled. | Canvas becomes non-empty during boot. Screenshot hashes or manual captures show expected dashboard/boot animation progress relative to native reference. |
| 6.5 Decide WebGL/WebGPU direction | If minimal scanout is insufficient, choose between a constrained WebGL 2 path and a new WebGPU NV2A backend. Do not try to force the OpenGL 4 renderer through WebGL unchanged. | Decision note includes missing GPU features, expected implementation cost, and a prototype test proving one NV2A operation renders correctly. |

Exit criteria:

- Browser run reaches B4, or the exact renderer gap blocking B4 is identified.
- Display work is based on measured gaps, not assumptions from the desktop OpenGL backend.

## Phase 7: Input, Audio, Networking, And Product Hardening

Goal: only after B3/B4, add the parts that make the booted system usable.

| Task | Work | Verification |
| --- | --- | --- |
| 7.1 Browser input | Map keyboard/gamepad browser events to the existing Xbox controller path without depending on SDL. | Browser Gamepad API or keyboard events change guest controller state in an input test and in dashboard navigation. |
| 7.2 Browser audio | Add an AudioWorklet-backed output path for MCPX APU samples, keeping noaudio as the default for smoke tests. | Audio test plays a stable tone or dashboard sound with bounded underruns and measured latency. |
| 7.3 Networking disabled by default | Keep NAT/UDP/PCAP unavailable in browser boot builds unless a WebSocket/WebRTC gateway is deliberately added later. | Browser boot has no raw network errors. UI clearly shows network disabled. |
| 7.4 Performance gate | Re-measure boot time, CPU usage, memory, storage latency, and frame latency after each major feature. | A performance report compares headless, storage, display, and audio builds. Regressions have thresholds and owners. |
| 7.5 CI smoke coverage | Add native headless and wasm headless smoke jobs using non-proprietary fixtures where possible. Keep proprietary boot fixtures local-only. | CI proves buildability and B0/B1-style synthetic boot markers; local private smoke proves B3/B4 with real assets. |

Exit criteria:

- Browser boot is repeatable by another developer with local legal assets.
- Failures produce logs and boot levels rather than vague browser crashes.

## Go/No-Go Gates

Gate 1: Native headless parity.

- Continue only if native headless/null reaches the same boot milestone as native desktop for B0-B3.
- If not, fix the harness before touching wasm.

Gate 2: Wasm build viability.

- Continue only if the reduced wasm target builds without desktop UI, OpenGL, Vulkan, libpcap, or SDL requirements.
- If this fails, the build-system work is still incomplete.

Gate 3: TCI speed.

- Continue to browser storage only if wasm TCI reaches B2 in reasonable time.
- If TCI is too slow to reach B2/B3, pause local-browser work and evaluate CPU alternatives: wasm-native TCG backend, separate x86-to-wasm translation, or server-side native xemu streaming.

Gate 4: Browser storage.

- Continue to visible display only if HDD random access works without preloading full images.
- If storage cannot be solved cleanly, visible boot work will be misleading because the dashboard path will not be realistic.

Gate 5: Renderer path.

- Continue beyond B4 only after deciding whether minimal scanout, WebGL 2, or WebGPU is the real path.
- Do not spend significant time adapting the desktop OpenGL 4 renderer unless a prototype proves the required features map cleanly.

## Suggested First Implementation Slice

The first slice should be small and prove the shape of the work:

1. Add boot markers and controlled timeout.
2. Add native headless/null boot harness.
3. Remove SDL from the null renderer Meson stanza.
4. Add a script that reports B0/B1/B2/B3 from logs.
5. Only then start the reduced wasm build profile.

Verification for the first slice:

```sh
scripts/xbox-boot-smoke.sh native-headless
```

Expected output shape:

```text
BOOT_MARK b0 machine=xbox renderer=NULL
BOOT_MARK b1 bios=loaded mcpx=loaded
BOOT_MARK b2 device=nv2a initialized
BOOT_MARK b2 device=mcpx-apu initialized
BOOT_MARK b3 ide=hdd first_read_lba=... nsectors=... method=... unit=... total_sectors=...
BOOT_SMOKE_RESULT level=B3 elapsed_ms=... exit=timeout
```

This gives the project a real boot ladder. If the wasm/browser work cannot reproduce the same markers in order, the next bug is local and concrete.

## Current Implementation Status

Updated through the native Docker/headless slice, reduced-profile headless entrypoint split, browser-profile SDL cut, browser-profile host-networking cut, browser-profile samplerate/audio dependency cut, and browser-profile OpenGL/GBM dependency cut:

- Boot markers are gated by `XEMU_BOOT_TRACE=1`.
- Headless boot mode is gated by `XEMU_HEADLESS_BOOT=1`.
- Headless runs use `-display none`, `-audio none`, and force the null renderer.
- The null renderer Meson stanza no longer depends on SDL.
- Docker native builds are available through `scripts/docker-build-xemu.sh`.
- Docker native builds can skip the image rebuild with `XEMU_DOCKER_SKIP_IMAGE_BUILD=1` when the local `xemu-native-build:latest` image already exists.
- Docker build scaffolding is statically checked by `scripts/xbox-docker-build-check.sh`, which verifies the native and wasm Dockerfiles plus the native, wasm, and wasm-sysroot build scripts preserve the required i386, TCI, browser-boot, and Emscripten sysroot settings.
- Native Docker smoke runs are available through `scripts/xbox-boot-smoke.sh docker-headless`.
- `scripts/xbox-real-fixture-layout.sh --create` creates only the ignored local fixture directory and README for real B3 assets; it never creates, copies, downloads, or modifies proprietary Xbox files.
- The smoke script validates `XEMU_MCPX` as 512 bytes and `XEMU_EEPROM` as 256 bytes when provided.
- The smoke script rejects empty `XEMU_FLASH` and `XEMU_HDD` files before emulation.
- The smoke script requires `XEMU_HDD` when `XEMU_SMOKE_EXPECT_LEVEL` is B3 or higher.
- The smoke script writes logs to `build-docker/boot-smoke/boot-smoke.log` and reports `BOOT_SMOKE_SUMMARY ...`.
- IDE HDD PIO/DMA first reads emit `BOOT_MARK b3 ide=hdd first_read_lba=... nsectors=... method=... unit=... total_sectors=...` when a real boot reaches storage; B3 smoke runs require that structured marker.
- `scripts/xbox-boot-smoke-selftest.sh` verifies the smoke parser without private assets, including B-level extraction, B3 structured HDD-read enforcement, missing `BOOT_SMOKE_RESULT`, and marker-rate metrics.
- Device thread startup is observable through gated markers for the QEMU main thread, NV2A PFIFO thread, MCPX APU frame thread, and MCPX voice workers.
- `xemu_browser_boot` is available as a Meson/configure option and currently selects a minimal headless entrypoint plus input, notification, and snapshot stubs.
- Browser-boot builds disable GL/Vulkan PGRAPH renderer source subdirectories while keeping the null renderer and GLSL helpers.
- Browser-boot builds exclude desktop `ui/xemu.c`, `ui/xui/*`, desktop input, ImGui, ImPlot, and `ui/thirdparty`.
- Browser-boot builds do not discover or link SDL. SDL-backed MCPX APU monitor and XBLC audio paths are compiled as browser no-ops, and browser profile uses `g_get_num_processors()` instead of `SDL_GetNumLogicalCPUCores()`.
- Browser-boot builds do not discover or link `libslirp` or `libpcap`. The generic pcap netdev initializer is guarded by `CONFIG_PCAP`, and the browser profile uses `ui/xemu-net-stubs.c` so the emulated NVNet device remains present while host networking stays disabled.
- Browser-boot builds do not discover or link `libsamplerate`. MCPX voice processing keeps the default `libsamplerate` path in normal builds, while the browser profile uses a direct sample path suitable for no-audio boot smoke work.
- Browser-boot builds do not discover or link OpenGL, epoxy, or GBM. `CONFIG_OPENGL` and `CONFIG_GBM` are undefined in the browser profile; the default profile still discovers them.
- A separate ignored `build-browser-probe/` directory can be used to test reduced-profile build changes without disturbing `build-docker/`.

Current verified evidence with synthetic non-proprietary fixtures:

```sh
scripts/xbox-browser-boot-verify-synthetic.sh
```

Result:

```text
BROWSER_BOOT_SYNTHETIC_VERIFY result=pass out_dir=/Users/samuelalaniz/dev/projects/xemu/build-browser-boot-verify-synthetic host=pass runtime=pass matrix=pass
```

This aggregate gate runs shell/JS syntax checks, the reduced wasm profile
verifier, fixture guard self-tests, the real fixture readiness self-test, the
self-contained boot smoke parser self-test, the real B3 wrapper self-test,
browser block storage checks, evidence-summary
self-tests, HTTP host verification, Playwright browser runtime smoke, the real
browser runtime missing-fixture guard, and the synthetic native-vs-wasm boot
matrix, then emits an evidence summary. It is the preferred no-private-assets
regression check before using real Xbox fixtures.

Evidence summary:

```sh
scripts/xbox-boot-evidence-summary.sh
```

Diagnostic completion audit:

```sh
scripts/xbox-boot-completion-audit.sh
```

Machine-readable next action:

```sh
scripts/xbox-boot-next-step.sh
```

Current expected result without private fixtures:

```text
XBOX_BOOT_NEXT result=next next=real-b3-assets reason=add-real-fixtures command_id=real-fixtures-ready command_json="scripts/xbox-real-fixtures-ready.sh" ...
```

To prepare the ignored local fixture directory without adding assets:

```sh
scripts/xbox-real-fixture-layout.sh --create
scripts/xbox-real-fixtures-ready.sh
```

Fixture privacy check:

```sh
scripts/xbox-fixture-privacy-check.sh
```

Expected result:

```text
FIXTURE_PRIVACY_RESULT result=pass repo=...
```

Current result:

```text
BOOT_EVIDENCE item=b3_browser_block_bridge status=synthetic-only ...
BOOT_EVIDENCE item=b3_real_assets status=missing ...
BOOT_EVIDENCE item=b4_visible_display status=missing ...
BOOT_EVIDENCE item=b5_real_browser status=missing ...
BOOT_EVIDENCE_SUMMARY result=incomplete synthetic_native=B2 synthetic_wasm=B2 real_b3=missing real_b4=missing real_b5=missing next=real-b3-assets ...
```

Human-readable status report:

```sh
scripts/xbox-boot-evidence-report.sh
```

Output: `xbox-browser-boot-status.md`.

Earlier individual command evidence:

```sh
XEMU_FLASH=/tmp/xemu-smoke-flash.bin \
XEMU_SMOKE_MS=500 \
XEMU_SMOKE_EXPECT_LEVEL=B0 \
scripts/xbox-boot-smoke.sh docker-headless
```

Result:

```text
BOOT_SMOKE_SUMMARY result=pass mode=docker-headless level=B2 expected=B0 exit=0
BOOT_MARK b0 thread=qemu-main created
BOOT_MARK b0 thread=qemu-main started
BOOT_MARK b2 thread=mcpx-voice-worker created id=0
BOOT_MARK b2 thread=mcpx-voice-worker started id=0
BOOT_MARK b2 thread=mcpx-apu-frame created
BOOT_MARK b2 thread=mcpx-apu-frame started
BOOT_MARK b2 thread=nv2a-pfifo created
BOOT_MARK b2 thread=nv2a-pfifo started
BOOT_SMOKE_RESULT reason=timeout elapsed_ms=... exit=0
```

Current verified evidence for the reduced-profile headless split plus SDL/network/audio/graphics dependency cuts:

```sh
XEMU_DOCKER_SKIP_IMAGE_BUILD=1 \
XEMU_DOCKER_BUILD_DIR=build-browser-probe \
XEMU_DOCKER_RECONFIGURE=1 \
XEMU_DOCKER_JOBS=8 \
scripts/docker-build-xemu.sh --enable-xemu-browser-boot
```

Result:

```text
build-browser-probe/qemu-system-i386 linked successfully
xemu_browser_boot : true
Subprojects do not include sdl3, imgui, or implot
No slirp, libpcap, libsamplerate, OpenGL, epoxy, or GBM dependency is discovered
```

Source exclusion check:

```sh
rg -n "subprojects/SDL3|SDL3|SDL_|ui_xemu\\.c|ui_xui_|ui_xemu-input\\.c|hw/xbox/nv2a/pgraph/gl/|hw_xbox_nv2a_pgraph_gl_|hw/xbox/nv2a/pgraph/vk/|hw_xbox_nv2a_pgraph_vk_|subprojects/imgui|subprojects/implot|ui/thirdparty|gloffscreen" \
  build-browser-probe/build.ninja build-browser-probe/compile_commands.json
```

Result: no matches for SDL, desktop UI, XUI, GL/VK renderer paths, ImGui, ImPlot, `ui/thirdparty`, or `gloffscreen`.

Network exclusion check:

```sh
rg -n "libslirp|/slirp|slirp\\.c|libpcap|net_pcap\\.c|net/pcap\\.c|ui_xemu-net\\.c|xemu-net\\.c" \
  build-browser-probe/build.ninja build-browser-probe/compile_commands.json

rg -n "ui_xemu-net-stubs\\.c|CONFIG_PCAP|CONFIG_SLIRP" \
  build-browser-probe/build.ninja build-browser-probe/compile_commands.json build-browser-probe/config-host.h
```

Result: no matches for the real slirp/pcap/xemu-net paths; `CONFIG_PCAP` and `CONFIG_SLIRP` are undefined; `ui_xemu-net-stubs.c` is compiled.

Audio dependency exclusion check:

```sh
rg -n "libsamplerate|samplerate\\.so|samplerate\\.h|src_callback|src_reset|src_float_to_short_array|SRC_" \
  build-browser-probe/build.ninja build-browser-probe/compile_commands.json

rg -n "Run-time dependency.*samplerate|samplerate" \
  build-browser-probe/meson-logs/meson-log.txt
```

Result: no matches in the browser-profile build graph or Meson log.

Graphics dependency exclusion check:

```sh
rg -n "Run-time dependency epoxy|Run-time dependency gbm|OpenGL support \\(epoxy\\).*YES|GBM.*YES|libepoxy|libGL\\.so|/libGL|/libepoxy|/libgbm|CONFIG_OPENGL 1|CONFIG_GBM 1" \
  build-browser-probe/meson-logs/meson-log.txt \
  build-browser-probe/build.ninja \
  build-browser-probe/compile_commands.json \
  build-browser-probe/config-host.h

rg -n "OpenGL support \\(epoxy\\)|GBM|CONFIG_OPENGL|CONFIG_GBM" \
  build-browser-probe/meson-logs/meson-log.txt \
  build-browser-probe/config-host.h
```

Result: no matches for OpenGL/epoxy/GBM dependency or link edges; `CONFIG_OPENGL` and `CONFIG_GBM` are undefined; summary reports `OpenGL support (epoxy): NO` and `GBM: NO`.

Source inclusion check:

```sh
rg -n "ui_xemu-headless\\.c|ui_xemu-input-stubs\\.c|ui_xemu-notifications-stubs\\.c|ui_xemu-snapshots-stubs\\.c|hw_xbox_nv2a_pgraph_null_renderer" \
  build-browser-probe/build.ninja build-browser-probe/compile_commands.json
```

Result: matches for the headless entrypoint, browser stubs, and null renderer.

Reduced-profile smoke check:

```sh
XEMU_FLASH=/tmp/xemu-smoke-flash.bin \
XEMU_SMOKE_BUILD_DIR=build-browser-probe \
XEMU_SMOKE_OUT_DIR=build-browser-probe/boot-smoke \
XEMU_SMOKE_MS=500 \
XEMU_SMOKE_EXPECT_LEVEL=B0 \
scripts/xbox-boot-smoke.sh docker-headless
```

Result:

```text
BOOT_SMOKE_SUMMARY result=pass mode=docker-headless level=B2 expected=B0 exit=0
BOOT_SMOKE_RESULT reason=timeout elapsed_ms=511 exit=0
```

Default-profile regression check after browser-only guards:

```sh
XEMU_DOCKER_JOBS=8 scripts/docker-build-xemu.sh

XEMU_FLASH=/tmp/xemu-smoke-flash.bin \
XEMU_SMOKE_MS=500 \
XEMU_SMOKE_EXPECT_LEVEL=B0 \
scripts/xbox-boot-smoke.sh docker-headless
```

Result:

```text
build-docker/qemu-system-i386 linked successfully
BOOT_SMOKE_SUMMARY result=pass mode=docker-headless level=B2 expected=B0 exit=0
BOOT_SMOKE_RESULT reason=timeout elapsed_ms=510 exit=0
```

Default-profile graphics regression evidence:

```sh
rg -n "Run-time dependency epoxy|Run-time dependency gbm|OpenGL support \\(epoxy\\)|GBM|libepoxy|libGL\\.so|/libGL|/libepoxy|/libgbm|CONFIG_OPENGL 1|CONFIG_GBM 1" \
  build-docker/meson-logs/meson-log.txt \
  build-docker/build.ninja \
  build-docker/compile_commands.json \
  build-docker/config-host.h
```

Result: default profile still discovers epoxy and GBM, defines `CONFIG_OPENGL` and `CONFIG_GBM`, and links `libGL`/`libepoxy`.

Wasm build container and first configure evidence:

```sh
XEMU_WASM_RECONFIGURE=1 \
XEMU_WASM_JOBS=8 \
scripts/docker-build-xemu-wasm.sh
```

Result:

```text
xemu-wasm-build:latest image builds from docker/xemu-wasm-build.Dockerfile
Meson enters a cross build with host machine cpu_family=wasm32 and compiler emcc/em++
TCG interpreter is enabled for i386-softmmu
Configure fails at host glib-2.0 lookup because no wasm pkg-config/sysroot exists yet
```

Wasm sysroot and link evidence:

```sh
scripts/docker-build-wasm-sysroot.sh

XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_RECONFIGURE=1 \
XEMU_WASM_JOBS=8 \
scripts/docker-build-xemu-wasm.sh
```

Result:

```text
Wasm sysroot builds zlib, PCRE2, libffi, and GLib for Emscripten.
libffi is patched for Emscripten 6 helper generation.
zlib is linked statically through the generated pkg-config file.
qemu-system-i386.js and qemu-system-i386.wasm link successfully.
Meson reports host cpu_family=wasm32, target list i386-softmmu, TCG backend TCI, static build YES.
SDL, OpenGL/epoxy, Vulkan, GBM, slirp, curl, and audio backends remain disabled.
```

Reduced wasm profile source verification:

```sh
scripts/xbox-verify-wasm-profile.sh build-wasm-pic
```

Result:

```text
WASM_PROFILE_CHECK result=pass build_dir=... compiled_sources=1979 wasm_bytes=18769651 js_bytes=304314
```

This verifies the wasm profile is `xemu_browser_boot=true`,
`CONFIG_TCG_INTERPRETER` is enabled, the target list is `i386-softmmu`, and the
headless entrypoint, null renderer, Xbox machine code, IDE core, JS artifact,
and wasm artifact are present. It also verifies desktop UI, XUI, SDL,
ImGui/ImPlot, PGRAPH GL/GLSL/Vulkan renderer sources, libpcap config, and
libsamplerate are absent from the compile profile.

Wasm Node smoke evidence with dummy firmware:

```sh
tmp_flash=/tmp/xemu-dummy-flash.bin
rm -f "$tmp_flash"
dd if=/dev/zero of="$tmp_flash" bs=1024 count=1024 status=none

XEMU_FLASH="$tmp_flash" \
XEMU_SMOKE_MS=500 \
XEMU_SMOKE_EXPECT_LEVEL=B0 \
XEMU_SMOKE_OUT_DIR=build-wasm-pic/boot-smoke \
scripts/xbox-boot-smoke.sh wasm-node-headless
```

Result:

```text
BOOT_SMOKE_SUMMARY result=pass mode=wasm-node-headless level=B2 expected=B0 exit=124
BOOT_SMOKE_RESULT reason=host-timeout elapsed_ms=500 exit=124
```

Notes:

- The wasm Node smoke imports the ES module factory, mounts the repo and fixture directory with NodeFS, and passes `-config_path` plus `-headless_boot_ms`.
- The Emscripten wasm profile keeps Asyncify enabled for `emscripten_fiber_swap`, disables Emscripten assertions, and post-links the generated pthread proxy helper so synchronous proxied calls can complete through `Promise.resolve(...)`.
- The Node host timeout emits the final smoke result because the Emscripten main thread can remain parked while worker threads run.
- This is dummy firmware evidence only. It proves wasm startup, B0/B1 marker emission, Xbox device construction through B2, worker startup, and deterministic smoke reporting. It does not prove real firmware execution or dashboard boot.

Next reduced-profile work:

- Run native and wasm smoke with the same real local Xbox assets, including a 512-byte MCPX ROM, 256-byte EEPROM, flash image, and HDD image when available.
- Compare native and wasm marker sequences before investigating browser-only behavior.
- Push from dummy B2 evidence to real B1/B2/B3 evidence: firmware execution starts, core devices show activity, and storage boot path performs real HDD/block reads.

Fixture preflight:

```sh
XEMU_MCPX=/path/to/mcpx.bin \
XEMU_FLASH=/path/to/flash.bin \
XEMU_EEPROM=/path/to/eeprom.bin \
XEMU_HDD=/path/to/xbox_hdd.img \
scripts/xbox-boot-fixtures-check.sh
```

Result expectation:

```text
BOOT_FIXTURE name=mcpx size=512 path=...
BOOT_FIXTURE name=eeprom size=256 path=...
BOOT_FIXTURE_RESULT result=pass
```

No-private-assets guard coverage:

```sh
scripts/xbox-boot-fixtures-check-selftest.sh
```

Result expectation:

```text
FIXTURE_SELFTEST case=missing-flash result=pass
FIXTURE_SELFTEST case=missing-file result=pass
FIXTURE_SELFTEST case=bad-mcpx-size result=pass
FIXTURE_SELFTEST case=bad-eeprom-size result=pass
FIXTURE_SELFTEST case=complete-fixtures result=pass
FIXTURE_SELFTEST_RESULT result=pass cases=5
```

Next verification with private local assets:

```sh
XEMU_MCPX=/path/to/mcpx.bin \
XEMU_FLASH=/path/to/flash.bin \
XEMU_EEPROM=/path/to/eeprom.bin \
XEMU_HDD=/path/to/xbox_hdd.img \
XEMU_SMOKE_MS=30000 \
scripts/xbox-boot-smoke-matrix.sh
```

Result expectation:

```text
BOOT_FIXTURE_RESULT result=pass
BOOT_SMOKE_SUMMARY result=pass mode=docker-headless level=B3 expected=B3 ...
BOOT_SMOKE_SUMMARY result=pass mode=wasm-node-headless level=B3 expected=B3 ...
BOOT_MARK_COMPARE result=pass mode=set baseline=B3 candidate=B3 expected=B3 ...
BOOT_MATRIX_RESULT result=pass expected=B3 compare=B3 ...
```

Native-vs-wasm marker comparison:

```sh
XEMU_COMPARE_MIN_LEVEL=B2 \
scripts/xbox-boot-compare-markers.sh \
  build-docker/boot-smoke/boot-smoke.log \
  build-wasm-pic/boot-smoke/boot-smoke.log
```

Result expectation:

```text
BOOT_MARK_COMPARE result=pass mode=set baseline=B... candidate=B... expected=B2 ...
```

Set comparison is the default because thread startup markers can arrive in
different order across native and wasm. Use `XEMU_COMPARE_STRICT_ORDER=1` when
investigating deterministic single-thread marker regions.

Smoke runs also emit a timing line:

```text
BOOT_SMOKE_METRIC mode=wasm-node-headless elapsed_ms=... markers=... markers_per_sec=... b0=... b1=... b2=... b3=...
```

Use this as an early TCI progress metric. It is not a guest instruction counter,
but it is stable enough to show whether wasm is still making boot progress and
whether increasing `XEMU_SMOKE_MS` is likely to reach the next milestone.

Synthetic harness check:

```sh
scripts/xbox-verify-wasm-profile.sh build-wasm-pic
scripts/xbox-boot-synthetic-matrix.sh
```

Observed result:

```text
WASM_PROFILE_CHECK result=pass build_dir=... compiled_sources=... wasm_bytes=... js_bytes=...
BOOT_MARK_COMPARE result=pass mode=set baseline=B2 candidate=B2 expected=B2 ...
BOOT_MATRIX_RESULT result=pass expected=B0 compare=B2 ...
BOOT_SYNTHETIC_MATRIX_RESULT result=pass out_dir=... fixture_dir=...
```

This only proves the harness, config propagation, Docker mounts, wasm Node
mounts, and marker comparison. It does not prove a real Xbox boot path because
the synthetic flash is zero-filled and no HDD read is expected.

Browser host shell evidence:

```sh
scripts/serve-xbox-browser-boot.py --port 8765
```

Result:

```text
BROWSER_BOOT_SERVER url=http://127.0.0.1:8765/browser/xbox-boot/ directory=...
```

Header verification:

```sh
scripts/xbox-browser-host-check.sh http://127.0.0.1:8765
```

Result:

```text
BROWSER_HOST_CHECK result=pass base_url=http://127.0.0.1:8774 index_bytes=2617 js_bytes=308029 wasm_bytes=18776552 isolation_headers=all synthetic=yes transcript_metadata=yes capabilities=yes config_persistence=yes eeprom_persistence=yes block_storage=yes opfs_sync=yes
```

Browser runtime verification:

```sh
scripts/xbox-browser-runtime-smoke.sh
```

Result:

```text
BROWSER_RUNTIME_SMOKE result=pass url="http://127.0.0.1:8781/browser/xbox-boot/" capabilities=yes mode=synthetic artifacts=yes asset_validate=yes config_persist=yes b3=not-required boot_result=timeout
```

Real browser runtime verification, after local fixtures are available:

```sh
XEMU_BROWSER_RUNTIME_MODE=real \
XEMU_BROWSER_RUNTIME_BOOT_MS=10000 \
scripts/xbox-browser-runtime-smoke.sh
```

This mode auto-discovers the same `fixtures/` or `xemu-fixtures/` layout as the
real B3 matrix, verifies timeout/build-directory/B3-requirement persistence
across a page reload, fills the browser file inputs through Playwright, enables
the B3 asset requirement, starts the selected-assets run, and requires either
`BOOT_MARK b3 browser_block=read` or `BOOT_MARK b3 ide=hdd` unless
`XEMU_BROWSER_RUNTIME_EXPECT_B3=0` is set.

The browser shell lives in `browser/xbox-boot/`. It validates flash, MCPX,
EEPROM, HDD, and DVD selections, reports `crossOriginIsolated`,
`SharedArrayBuffer`, `Worker`, `BigInt`, and `WebAssembly`, starts the wasm ES
module in a worker, captures logs, supports stop, and exports a transcript. It
also has a no-private-assets synthetic run mode that creates a 1 MiB zero-filled
flash fixture and emits `BROWSER_RUN_MODE mode=synthetic-zero-flash`. The
transcript includes `BROWSER_USER_AGENT`, `BROWSER_LOCATION`,
`BROWSER_CAPABILITY`, `BROWSER_ARTIFACT`, selected asset metadata,
`BROWSER_ASSET_VALIDATE`, boot logs, and `BROWSER_BOOT_RESULT`. Timeout, build
directory, and the B3 asset requirement are saved to local storage and restored
on reload, with `BROWSER_CONFIG persisted=yes` emitted in transcripts. The
worker exports the current 256-byte EEPROM on timeout, module return, or error
using `BROWSER_EEPROM_EXPORT`; the main thread stores it in local storage and
restores it on later runs when no EEPROM file is selected using
`BROWSER_EEPROM_PERSIST`. The main page also owns a watchdog timeout that can
terminate a busy wasm worker and emit `BOOT_SMOKE_RESULT
reason=browser-main-timeout` plus `BROWSER_BOOT_RESULT result=timeout`.

This satisfies the local shell, isolation-header, validation, and transcript
export parts of Phase 4, plus small config and EEPROM persistence from Phase
4.4. It does not solve Phase 5 random-access storage; selected HDD/DVD files
are still mounted as ordinary browser-provided buffers for small boot
experiments.

### Phase 5.1/5.2 browser block storage groundwork

The first browser storage slice is a standalone random-access block helper:

```sh
scripts/xbox-browser-block-selftest.mjs
scripts/xbox-browser-block-persistence-smoke.sh
```

Expected result:

```text
BROWSER_BLOCK_SELFTEST result=pass image_bytes=16777216 sector_size=512 random_reads=96 blob_read_calls=97 blob_bytes_read=151555 overlay_chunks=4 overlay_bytes_written=8265 overlay_snapshot_chunks=4 overlay_reload_readback=yes overlay_serialized_bytes=... overlay_persisted_readback=yes sync_snapshot_chunks=... sync_snapshot_readback=yes ...
BROWSER_BLOCK_PERSISTENCE_SMOKE result=pass target=indexedDB chunks=... serialized_bytes=... readback=yes
```

The rebuilt wasm profile also contains the C-side callback bridge:

```text
WASM_PROFILE_CHECK result=pass build_dir=/Users/samuelalaniz/dev/projects/xemu/build-wasm-pic compiled_sources=1979 wasm_bytes=18776552 js_bytes=308029
build-wasm-pic/qemu-system-i386.js: function xemu_browser_block_open(...)
```

The pthread-safe C-to-JS callback bridge is covered by the synthetic matrix,
which now runs a synthetic HDD browser-block smoke after the native/wasm B2
marker comparison:

```sh
scripts/xbox-boot-synthetic-matrix.sh
```

Result:

```text
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=synthetic open=yes read=yes hdd_bytes=16777216 log=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix/browser-block/browser-block-callback-smoke.log
BROWSER_BLOCK_OPEN result=pass id=1 asset=hdd backend=node-synthetic writable=no size=16777216
BOOT_MARK b3 browser_block=open path=/xemu-browser-block/xbox_hdd.img id=1 bytes=16777216
BROWSER_BLOCK_READ result=pass id=1 asset=hdd backend=node-synthetic offset=0 bytes=512
BOOT_MARK b3 browser_block=read id=1 offset=0 bytes=512
```

The same no-private-assets synthetic matrix still passes native/wasm B2 marker
comparison after the browser-block bridge:

```text
BOOT_MATRIX_RESULT result=pass expected=B0 compare=B2 out_dir=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix
BOOT_SYNTHETIC_MATRIX_RESULT result=pass out_dir=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix fixture_dir=/tmp/xemu-synthetic-fixtures
```

This proves deterministic random sector reads from a `Blob`/`File` source,
byte-range reads at non-sector offsets, out-of-range failure behavior, sparse
write/readback through an overlay device, reloading exported overlay chunks
over the same base image, and a JSON/base64 snapshot round trip suitable for
browser persistence. The self-test also proves the synchronous memory helper
used by the C callback path can restore its serialized snapshot over the base
image. The browser IndexedDB smoke proves the same snapshot format can be
persisted and restored in a real cross-origin-isolated browser context. The
browser worker now uses the same helper to emit
`BROWSER_BLOCK_PROBE` for selected HDD/DVD files before
module startup, and QEMU is configured to use `/xemu-browser-block/...` paths
that call back into worker-owned storage from the raw file driver. On browsers
with OPFS sync access handles, the callback storage no longer requires the
whole HDD/DVD image to live in JS heap. The callback bridge is now
pthread-safe through main-thread synchronous proxying and is proven with a
synthetic HDD open/read smoke. Memory fallback writes have a snapshot handoff
marker for later durable storage integration:

```text
BROWSER_BLOCK_SNAPSHOT result=pass ... chunks=... serialized_bytes=...
BROWSER_BLOCK_SNAPSHOT_LOAD result=pass ... source=indexedDB ...
BROWSER_BLOCK_SNAPSHOT_PERSIST result=pass ... target=indexedDB ...
```

This still does not prove real B3 HDD boot reads from a dashboard-capable HDD
image until a browser run emits
`BOOT_MARK b3 browser_block=read` from real assets.

For private local B3 validation, set at least `XEMU_FLASH` and `XEMU_HDD`,
optionally `XEMU_MCPX` and `XEMU_EEPROM`, then run:

```sh
XEMU_FLASH=/path/to/flash.bin \
XEMU_HDD=/path/to/xbox_hdd.img \
XEMU_SMOKE_MS=10000 \
scripts/xbox-real-b3-matrix.sh
```

Alternatively, place untracked fixtures at `fixtures/` or `xemu-fixtures/`
using the standard names `flash.bin`, `xbox_hdd.img`, optional `mcpx.bin`,
optional `eeprom.bin`, and optional `dvd.iso`; then run the same script without
fixture env vars. Use `XEMU_REAL_B3_FIXTURE_DIR=/path/to/fixtures` for another
local directory.

First validate fixture discovery and sizes without starting emulation:

```sh
scripts/xbox-real-fixtures-ready.sh
scripts/xbox-real-fixture-manifest.sh
```

Expected readiness result when local private assets are present:

```text
REAL_FIXTURE_READY item=flash status=present bytes=... path=...
REAL_FIXTURE_READY item=hdd status=present bytes=... path=...
REAL_FIXTURE_READY item=mcpx status=present bytes=512 path=...
REAL_FIXTURE_READY item=eeprom status=present bytes=256 path=...
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=0
```

If assets are not present yet, this command reports
`REAL_FIXTURE_READY_RESULT result=missing-required` and exits 0 by default so
handoff/status reports can stay green. Set `XEMU_REAL_FIXTURE_READY_REQUIRE=1`
when a missing or invalid fixture should fail the command.
Empty required flash/HDD files report `status=empty` and
`REAL_FIXTURE_READY_RESULT result=fail next=fix-fixtures`.
For isolated negative tests, set `XEMU_REAL_FIXTURE_IGNORE_REPO_DIRS=1` to
ignore repo-local `fixtures/` and `xemu-fixtures/` auto-discovery while still
honoring explicit `XEMU_REAL_B3_FIXTURE_DIR` and fixture path environment
variables.

`scripts/xbox-real-fixture-manifest.sh` writes
`build-real-fixture-manifest/real-fixture-manifest.md`, plus readiness and git
privacy logs. The manifest is a handoff artifact only: it records paths, sizes,
and privacy status without copying, hashing, or inspecting proprietary fixture
contents.

Then run the stricter B3 preflight wrapper:

```sh
XEMU_REAL_B3_PREFLIGHT_ONLY=1 scripts/xbox-real-b3-matrix.sh
```

Expected preflight result:

```text
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=1
BOOT_REAL_B3_PREFLIGHT_RESULT result=pass ...
```

Expected real-asset result:

```text
BOOT_REAL_B3_AUTODETECT name=XEMU_FLASH path=...
BOOT_REAL_B3_AUTODETECT name=XEMU_HDD path=...
REAL_FIXTURE_READY_RESULT result=pass next=real-b3-preflight require=1
BOOT_FIXTURE_RESULT result=pass
BOOT_MATRIX_RESULT result=pass expected=B3 compare=B3 ...
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=real open=yes read=yes hdd_bytes=...
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real ... run_mode=selected-assets ... hdd_asset=yes ... b3_marker=browser-block ...
BROWSER_RUNTIME_SMOKE result=pass ... mode=real ... config_persist=yes ... b3=required ...
BOOT_REAL_B3_MATRIX_RESULT result=pass native_wasm=pass browser_block=pass browser_runtime=pass ...
```

The wrapper first records `scripts/xbox-real-fixtures-ready.sh` output with
`XEMU_REAL_FIXTURE_READY_REQUIRE=1` after generating a no-emulation fixture
manifest, then runs `scripts/xbox-boot-fixtures-check.sh`, then runs the
native/wasm smoke matrix at B3, then runs the browser-block callback smoke with
the same real assets, then runs the browser selected-assets runtime smoke with
B3 required. Evidence is captured under `build-real-b3-matrix/`, including
`real-fixture-manifest.log`,
`real-fixture-manifest/real-fixture-manifest.md`, `real-fixture-ready.log`,
`fixtures.log`, `native/boot-smoke.log`, `wasm/boot-smoke.log`, `compare.log`,
`browser-block/browser-block-callback-smoke.log`, `browser-runtime.log`, and
`real-b3-matrix.log`. The evidence summary and next-step helper prefer
`build-real-b3-matrix/` readiness and manifest outputs when present, so a
successful real preflight updates the handoff without rerunning the synthetic
aggregate.
Full non-preflight runs then invoke
`scripts/xbox-real-b3-evidence-check.sh` automatically and append
`REAL_B3_EVIDENCE result=pass ...` to `real-b3-matrix.log`.

Validate the final real B3 log contract with:

```sh
scripts/xbox-real-b3-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log
```

No-private-assets coverage for the real B3 wrapper:

```sh
scripts/xbox-real-b3-matrix-selftest.sh
scripts/xbox-real-b3-evidence-check-selftest.sh
```

Result:

```text
REAL_B3_SELFTEST result=pass autodetect=yes fixture_check=yes preflight_only=yes bad_fixture_guard=yes
REAL_B3_EVIDENCE_SELFTEST_RESULT result=pass cases=6
```

### B4/B5 evidence contract

The evidence summary intentionally keeps B4 and B5 missing until the real log
contains stronger proof than generic startup markers.

B4 requires both a display-path marker and a non-empty browser capture marker:

```text
BOOT_MARK b4 display=visible ...
BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes hash=... source=browser-canvas
```

Validate the B4 log contract with:

```sh
scripts/xbox-display-capture-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log
```

No-private-assets coverage for that contract:

```sh
scripts/xbox-browser-display-capture-smoke.sh
scripts/xbox-display-capture-evidence-check-selftest.sh
```

Expected result:

```text
BROWSER_DISPLAY_CAPTURE_SMOKE result=pass source=synthetic-framebuffer hash=...
DISPLAY_CAPTURE_EVIDENCE result=pass ... source=synthetic-framebuffer
DISPLAY_CAPTURE_EVIDENCE_SELFTEST_RESULT result=pass cases=6
```

This synthetic framebuffer smoke proves browser canvas capture, hashing, and
the B4 evidence parser. It is not real B4 completion; real B4 still requires
`build-real-b3-matrix/real-b3-matrix.log` to contain a real display-path marker
and a non-empty browser capture from the boot path.

B5 requires the real selected-assets browser smoke to prove the browser path is
usable, not just that the page loaded:

```text
BROWSER_RUNTIME_TRANSCRIPT result=pass mode=real run_mode=selected-assets hdd_asset=yes b3_marker=browser-block ...
BROWSER_RUNTIME_SMOKE result=pass ... capabilities=yes mode=real artifacts=yes asset_validate=yes config_persist=yes ...
```

Validate the B5 log contract with:

```sh
scripts/xbox-browser-runtime-evidence-check.sh build-real-b3-matrix/real-b3-matrix.log
```

No-private-assets coverage for that contract:

```sh
scripts/xbox-browser-runtime-evidence-check-selftest.sh
```

Expected result:

```text
BROWSER_RUNTIME_EVIDENCE_SELFTEST_RESULT result=pass cases=7
```

In real mode, the Node browser-block smoke mounts the HDD read-only and serves
callback reads with `fs.readSync()` against the mounted file descriptor instead
of preloading the full image into JS memory. Real mode fails if
`browser_block=read` is not observed. The synthetic matrix still passes with
this stricter real-mode gate:

```text
BOOT_MATRIX_RESULT result=pass expected=B0 compare=B2 out_dir=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix
BROWSER_BLOCK_CALLBACK_SMOKE result=pass mode=synthetic open=yes read=yes hdd_bytes=16777216 log=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix/browser-block/browser-block-callback-smoke.log
BOOT_SYNTHETIC_MATRIX_RESULT result=pass out_dir=/Users/samuelalaniz/dev/projects/xemu/build-synthetic-boot-matrix fixture_dir=/tmp/xemu-synthetic-fixtures
```
