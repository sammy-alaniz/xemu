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
| B6 | Dashboard is loaded and identifiable | Logs prove the dashboard XBE was read/loaded/executed, and browser frames match native reference frames closely enough to treat the dashboard as loaded rather than merely producing non-empty scanout |

The first serious browser-port gate is B3, not B4. A null-renderer browser build that reaches B3 proves most non-graphics boot blockers have been cleared.

Current long-term target after the completed B3/B4/B5 evidence chain is B6:
make "dashboard loaded" a verifiable state. B6 is intentionally stronger than
B4. B4 only proves real non-empty browser display output; B6 must prove the
dashboard path itself was reached and rendered with recognizable fidelity. The
active goal is to add reliable dashboard/XBE read-load-execute markers, capture
native reference frames, use Playwright-preferred browser visual capture with
Firefox BiDi fallback, compare browser frames to native references, and keep an
auditable B6 evidence checker that never treats non-empty scanout alone as
dashboard completion.

For current B6 work, treat `goal.md` as the live state machine: it names the
active artifact roles, loop guards, progress metric, next three actions, and
commands to start from. This plan preserves the boot ladder and evidence
contract; do not use older diagnostic history here to override `goal.md`.
Every experiment/run should also produce a numbered markdown write-up under
`history/` using the template there, so the project keeps an auditable trail of
purpose, findings, and follow-up decisions.
If progress stalls or the next run would repeat a historical/negative-control
path, use the independent critique checkpoint defined in `goal.md`: ask a
highest-reasoning sub-agent, preferably `gpt-5.5` with `xhigh` reasoning, to
critique whether the work is looping and what narrow fact would change the B6
boundary.

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

Current Phase 6 status:

- B4 has been proven with `source=browser-framebuffer` and
  `BROWSER_DISPLAY_CAPTURE result=pass nonempty=yes`.
- The current browser display can look noisy or partial because it is a
  framebuffer/scanout bridge on top of the reduced browser/null-rendered boot
  profile, not a full browser NV2A renderer.
- Do not treat B4 as "dashboard fully loaded." The next proof target is B6.

## Phase 6.6: B6 Dashboard Loaded Evidence

Goal: replace visual guesswork with a specific, auditable dashboard-loaded
signal.

| Task | Work | Verification |
| --- | --- | --- |
| 6.6.1 FATX/XBE read correlation | Map IDE guest-LBA reads back to FATX files and detect reads from dashboard XBE candidates such as `xboxdash.xbe`. | Log emits `BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...` with file name, byte range, and backing sector evidence for final B6; native-headless matches are diagnostic only. |
| 6.6.2 XBE load detection | Detect XBE headers and image load into guest memory. | Log emits `BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime ...` with guest address and image metadata, plus `dashboard=xbe-entry-probe status=ready entry_code_read=yes phys_match=yes` to prove the decoded entry page is readable and physically matched without logging proprietary content. |
| 6.6.3 XBE execution detection | Detect CPU execution entering the loaded dashboard XBE region. | Log emits `BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime ...` after code fetch or control transfer into the loaded range. |
| 6.6.3a High-alias false-positive guard | For high-bit PCs that numerically overlap the XBE virtual range, compare executing code hashes against the loaded low XBE image bytes without dumping proprietary bytes. | Diagnostic log emits bounded `dashboard=xbe-alias-compare ... phys_match=<yes/no> code_hash_match=<yes/no>`; it must not satisfy B6 by itself. |
| 6.6.3b Alias hash audit helper | Aggregate high-alias compare samples and compare their hashes with the dashboard XBE file bytes without dumping proprietary bytes. | `scripts/xbox-dashboard-xbe-hash-evidence.py --hdd <hdd> --log <log> --require-context browser-runtime` emits `DASHBOARD_XBE_HASH_EVIDENCE ...`; it is diagnostic only and must not satisfy B6 by itself. |
| 6.6.3c Entry-target hash guard | For decoded branch targets near the dashboard entry point, hash the target bytes and corresponding low XBE image bytes without dumping proprietary bytes. | Diagnostic log emits bounded `dashboard=xbe-entry-target-probe ... target_code_hash=... target_image_code_hash=...`; the hash audit helper reports `target_disk_hash_match=<n>`. It must not satisfy B6 by itself. |
| 6.6.4 Native reference frames | Capture native xemu reference frames using the same legal local assets and build metadata. | Reference artifacts record build hash, asset identity hashes that do not expose content, frame dimensions, and perceptual/hash summaries, then emit `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`. `scripts/xbox-native-reference-evidence-check.sh <log>` validates that provenance. |
| 6.6.5 Browser frame comparison | Capture browser canvas frames with Playwright when available and Firefox BiDi fallback otherwise. Compare against native references supplied with `XEMU_BROWSER_DASHBOARD_NATIVE_HASH=<native-frame-hash>`. | Log emits `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes ...` whose `native_hash` matches a validated `NATIVE_DASHBOARD_REFERENCE` line. By default `XEMU_BROWSER_DASHBOARD_CAPTURE_REQUIRE_EXECUTED=1` makes this evidence skip until browser-runtime `dashboard=xbe-executed` exists. |
| 6.6.6 B6 evidence checker | Add a dedicated checker for dashboard-loaded proof. | `scripts/xbox-dashboard-loaded-evidence-check.sh <log>` passes only when browser-runtime XBE read/load/entry-ready/execute, native reference provenance, and visual reference evidence are present; `scripts/xbox-dashboard-loaded-evidence-check-selftest.sh` covers the checker contract. |

Exit criteria:

- Browser log contains explicit dashboard XBE read/load/entry-ready/execute markers.
- Combined B6 evidence contains `NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless ... dashboard=xbe-executed ...`.
- Browser display evidence matches native reference frames closely enough to
  distinguish dashboard output from random/non-empty scanout.
- Completion audit has a separate B6 item and does not infer B6 from B4.

B6 evidence contract:

```text
BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=<name>.xbe ...
BOOT_MARK b6 dashboard=xbe-loaded context=browser-runtime guest_addr=0x... source=virtual-header ...
BOOT_MARK b6 dashboard=xbe-entry-probe context=browser-runtime status=ready entry_code_read=yes phys_match=yes ...
BOOT_MARK b6 dashboard=xbe-executed context=browser-runtime guest_pc=0x... ...
NATIVE_DASHBOARD_REFERENCE result=pass context=native-headless source=native-framebuffer hash=<hex> width=<n> height=<n> dashboard=xbe-executed ...
BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes hash=<hex> native_hash=<hex> source=browser-framebuffer width=<n> height=<n>
```

The B6 checker validates this contract only; it does not generate dashboard
evidence. The current implementation can correlate native-headless IDE guest
LBA reads to the dashboard XBE, but B6 still requires browser-runtime
dashboard read/load/entry-ready/execute markers and native reference-frame comparison
before it can pass. The browser-runtime read side is proven in the Firefox
BiDi IDE-poll diagnostic path, and focused read-progress diagnostics now prove
browser-runtime `dashboard=xbe-loaded source=virtual-header` plus entry-ready
probing. Entry readiness is a required precondition, not execution evidence.
The current alias-compare diagnostic also proves sampled high-alias overlaps
in `build-real-b3-matrix/browser-runtime-firefox-bidi-alias-compare-combined.log`
have `phys_match=no` and `code_hash_match=no`. The current alias hash audit
also reports `samples=32 comparable=32 guest_image_hash_match=0
guest_disk_hash_match=0`, with two low-image samples matching the disk hash
under the raw image-offset model. Those sampled high-alias paths are kernel
paths, not dashboard bytes executed through a different alias.
The entry-target diagnostic now also hashes decoded branch target bytes and the
corresponding low XBE image bytes, then the hash audit helper reports
`target_disk_hash_match` and `target_image_disk_hash_match`. The fresh
`build-real-b3-matrix/browser-runtime-firefox-bidi-target-hash-v1.log` artifact
reports `target_samples=16 target_comparable=16 target_disk_hash_match=0`, so
the sampled decoded targets also do not match dashboard file bytes. This is a
diagnostic guard only: a target hash match would identify a handoff candidate
to investigate, but B6 still requires actual browser-runtime `xbe-executed`
evidence plus a native reference-frame match.
The active B6 blocker is browser-runtime `dashboard=xbe-executed` evidence plus
native reference-frame match.

Current B6 implementation status:

- `xemu-xbe.c` contains `xemu_get_xbe_info()`, which reads the current XBE
  header from guest virtual address `0x10000` and exposes base, image size,
  entry, certificate, and title ID metadata without dumping proprietary XBE
  contents.
- `xemu_xbe_boot_trace_probe()` emits
  `BOOT_MARK b6 dashboard=xbe-loaded ... source=virtual-header` once when the
  virtual loaded-image XBE header appears. Its optional physical RAM scan emits
  `BOOT_MARK b6 dashboard=xbe-header-resident ... source=physical-scan` only as
  a diagnostic; that marker must not satisfy B6.
- The same probe emits `BOOT_MARK b6 dashboard=xbe-executed ...` once the
  synchronized i386 CPU program counter enters the loaded XBE image range.
- `xemu_xbe_boot_trace_entry_probe()` emits bounded
  `BOOT_MARK b6 dashboard=xbe-entry-probe ... status=unreadable|ready`
  diagnostics around the decoded dashboard entry point. A `status=ready` entry
  probe proves the entry code became readable and physically matched the loaded
  image, but it is not execution evidence and must not satisfy B6 by itself.
- `xemu_xbe_boot_trace_entry_target_probe()` emits bounded
  `BOOT_MARK b6 dashboard=xbe-entry-target-probe ...` diagnostics when decoded
  branch targets fall within a configurable window around the dashboard entry
  point. The knobs are `XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_LIMIT` and
  `XEMU_BOOT_TRACE_XBE_ENTRY_TARGET_WINDOW`. These markers include hashed
  branch-target and low-image bytes (`target_code_hash` and
  `target_image_code_hash`) without dumping proprietary content. They are
  diagnostic only and must not satisfy B6 by themselves.
- `xemu_xbe_boot_trace_dispatch_probe()` emits bounded
  `BOOT_MARK b6 dashboard=xbe-dispatch-probe ...` diagnostics after the
  decoded entry point is readable. It summarizes whether registers or the top 16
  stack words contain direct dashboard-image, entry-near, or high-alias
  mismatch candidates. The knob is `XEMU_BOOT_TRACE_XBE_DISPATCH_LIMIT`. The
  probe hashes stack bytes and logs candidate classifications instead of raw
  stack contents. These markers are diagnostic only and must not satisfy B6 by
  themselves.
- `xemu_xbe_boot_trace_kernel_loop_probe()` emits bounded
  `BOOT_MARK b6 dashboard=kernel-loop-probe ...` diagnostics from edge and
  transition-sample observations after the decoded entry point is readable. The knobs
  are `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT` and
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS`. The marker includes CPU
  interrupt/halt/exit state plus decoded branch and memory operand summaries
  when readable, including operand widths, virtual region, physical mapping,
  physical address, and targeted two-byte `movzx`/`movsx` memory forms
  (`0F B6`, `0F B7`, `0F BE`, `0F BF`). These markers are diagnostic only and
  must not satisfy B6 by themselves.
- Verbose TCG execution diagnostics still check for `dashboard=xbe-executed`
  immediately after `dashboard=xbe-loaded`, but their finite probe budgets are
  reserved until `dashboard=xbe-entry-probe status=ready` so post-entry handoff
  evidence is not exhausted while the entry page is unreadable. Post-entry
  execution diagnostic markers include `entry_ready=yes`.
- `xemu_xbe_boot_trace_phys_compare_probe()` emits bounded
  `BOOT_MARK b6 dashboard=xbe-phys-compare ... result=match|no-match`
  diagnostics after the decoded entry point is readable. The knob is
  `XEMU_BOOT_TRACE_XBE_PHYS_COMPARE_LIMIT`. The probe compares the executing
  translated block's guest physical address against the physical pages backing
  the loaded XBE virtual image and hashes matched bytes without dumping raw code.
  These markers are diagnostic only and must not satisfy B6 by themselves.
- `hw/xbox/nv2a/pmc.c` emits bounded
  `BOOT_MARK b6 nv2a=pmc-access ...` diagnostics for `NV_PMC_INTR_0` and
  `NV_PMC_INTR_EN_0`. The knob is `XEMU_BOOT_TRACE_NV2A_PMC_LIMIT`. The marker
  includes PMC pending/enabled state before and after access plus
  PFIFO/PCRTC/PGRAPH/PTIMER pending/enabled state. These markers are
  diagnostic only and must not satisfy B6 by themselves.
- The NV2A PCRTC/PGRAPH interrupt paths emit bounded
  `BOOT_MARK b6 nv2a=irq-source ...` diagnostics for source transitions such
  as PCRTC `vblank-raise` and PGRAPH `context-switch-raise` or
  `notify-error-raise`. The knob is `XEMU_BOOT_TRACE_NV2A_IRQ_LIMIT`.
  Pre-dashboard browser `pcrtc vblank-raise` events are suppressed for this
  diagnostic so they do not saturate the B6 IRQ-source budget before dashboard
  DMA/header observation. These markers are diagnostic only and must not
  satisfy B6 by themselves.
- The PGRAPH nonzero-NOP notification path emits bounded
  `BOOT_MARK b6 pgraph=notify-error ...` diagnostics with the actual NOP
  parameter, trapped data, PFIFO DMA get/put/state, interrupt state, and
  `waiting_nop` state at notification raise time. The knob is
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT`. These markers are diagnostic only
  and must not satisfy B6 by themselves.
- The PGRAPH notify-clear path emits bounded
  `BOOT_MARK b6 pgraph=notify-clear ...` diagnostics when the guest clears a
  notify-error condition through `NV_PGRAPH_INTR`. The marker records before
  and after pending bits, wait flags, PFIFO DMA state, trapped data, and
  PMC/PFIFO/PCRTC state. The knob is
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT`, falling back to
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT` when unset. These markers are
  diagnostic only and must not satisfy B6 by themselves.
- The NV2A aggregate IRQ line path emits bounded
  `BOOT_MARK b6 nv2a=irq-line ...` diagnostics. The total knob is
  `XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LIMIT`; low-priority PCRTC/PMC/idle samples are
  separately capped by `XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT` so late
  PGRAPH/PFIFO transitions remain visible. These markers are diagnostic only
  and must not satisfy B6 by themselves.
- The NV2A PFIFO path emits bounded
  `BOOT_MARK b6 pfifo=progress ...` diagnostics after `dashboard=xbe-loaded`
  and before accepted `dashboard=xbe-executed` evidence. The knob is
  `XEMU_BOOT_TRACE_NV2A_PFIFO_LIMIT`. The marker summarizes pusher/puller
  progress, method entries, waiting flags, FIFO access, and PMC/PGRAPH state.
  These markers are diagnostic only and must not satisfy B6 by themselves.
- The NV2A PGRAPH path emits bounded
  `BOOT_MARK b6 pgraph=method ...` diagnostics after dashboard DMA/header
  observation and before accepted `dashboard=xbe-executed` evidence. The knob
  is `XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_LIMIT`. The marker summarizes method
  enter/exit/unhandled phases, method metadata, interrupt state, wait flags,
  context state, surface state, trap state, and PMC state. These markers are
  diagnostic only and must not satisfy B6 by themselves.
- `accel/tcg/cpu-exec.c` also calls
  `xemu_xbe_boot_trace_observe_exec(..., "tcg-tb")` for translated block
  execution PCs in native Xbox and browser-boot builds, so execution detection
  is no longer dependent only on the coarse timeout-loop CPU PC sample.
- `ui/xemu-headless.c` polls the XBE probe from the shared native/wasm/browser
  timeout loop under the main loop lock, so native and browser runs get the
  same B6 loaded/executed marker behavior.
- The generic XBE loaded/executed markers include a boot trace context from
  `XEMU_BOOT_TRACE_CONTEXT` or a small `boot_trace_context.txt` file in the
  mounted fixture/smoke path; browser runtime passes `context=browser-runtime`,
  native smoke passes `context=native-headless`, and the Node block bridge
  passes `context=browser-block-callback`.
- `hw/ide/core.c` emits bounded guest logical HDD sector read markers before
  block backends translate them to host/qcow2 offsets. The read limit is
  controlled by `XEMU_BOOT_TRACE_IDE_READ_LIMIT` and defaults to 512 reads.
- `block/file-posix.c` and `browser/xbox-boot/worker.js` are still useful for
  proving browser-side bytes were served, but their offsets can be qcow2/host
  file offsets. Use IDE guest LBA evidence plus a FATX file map for
  `BOOT_MARK b6 dashboard=xbe-read context=browser-runtime file=xboxdash.xbe ...`.
- `scripts/xbox-dashboard-xbe-read-evidence.py` maps HDD images through FATX,
  finds dashboard XBE candidates such as `xboxdash.xbe`, and emits
  `BOOT_MARK b6 dashboard=xbe-read ... source=ide-read-log` when a guest-LBA
  read overlaps the dashboard file. It labels each match with a context such as
  `native-headless`, `wasm-node-headless`, or `browser-runtime`.
- Current real evidence shows `xboxdash.xbe` at `start_lba=4609192`. Native
  headless overlaps that file at `read_lba=4609192`, and the standard real
  matrix plus the Firefox BiDi IDE-poll diagnostic now overlap the same file in
  `context=browser-runtime` at read index 20.
- Historical browser-runtime probes before the IDE AIO-poll fix stalled after
  the first IDE HDD read at `read_lba=3`, while native immediately continued
  to FATX at `read_lba=4609024` and `xboxdash.xbe` at `read_lba=4609192`.
  Keep those logs as regression evidence, not as the current blocker.
- Use Firefox BiDi as the current practical long-run browser-runtime probe
  while keeping Playwright support for browser automation and future
  reference-frame work.
- `scripts/xbox-browser-runtime-smoke.sh` can now select the Playwright engine
  with `XEMU_BROWSER_RUNTIME_BROWSER=chromium` or `firefox`. Synthetic
  Playwright Chromium and Firefox runs pass on this machine.
- A real selected-assets Playwright Firefox probe
  (`build-real-b3-matrix/browser-runtime-playwright-firefox.log`) passes the
  browser runtime smoke and browser-block B3 requirement, but within a 60
  second boot window it does not reach B4 display capture or any IDE
  guest-LBA markers. Keep Firefox BiDi as the practical long-run probe until
  Playwright Firefox catches up.
- Deeper B3/B6 DMA diagnostics showed the first browser-runtime IDE DMA read
  was submitted and the browser block backend returned bytes for the real HDD,
  but the block AIO/DMA completion callback did not fire afterward. The fix is
  to poll the current AIO context after IDE stores the returned DMA AIOCB, not
  immediately inside the lower-level DMA helper before IDE owns the AIOCB.
- Current browser-runtime storage evidence has advanced past that stall:
  `build-real-b3-matrix/browser-runtime-firefox-bidi-ide-poll.log` reaches
  dashboard reads, including `read_lba=4609192` for `xboxdash.xbe`. The
  correlator emits
  `BOOT_MARK b6 dashboard=xbe-read context=browser-runtime ...`, and the
  standard matrix log still fails the B6 loaded checker at
  `missing-xbe-loaded-marker`; the newer focused artifact below advances past
  that boundary.
- A 60s native diagnostic from `build-docker-b6-xbe-scan`
  (`build-real-b3-matrix/native-60s-xbe-scan/boot-smoke.log`) also reads
  `xboxdash.xbe` but emitted no `dashboard=xbe-loaded`/`dashboard=xbe-executed`
  before the read-progress hook was added.
- A newer focused native diagnostic
  (`build-real-b3-matrix/native-60s-xbe-dma-buffer/boot-smoke.log`) emits
  `BOOT_MARK b6 dashboard=xbe-dma-buffer ... source=ide-dma-buffer` for the
  first dashboard read. It proves the `xboxdash.xbe` header reaches guest IDE
  DMA memory at `sg_addr=0x000be000`, with `image_base=0x00010000`, but it is
  diagnostic only. It does not replace `dashboard=xbe-loaded
  source=virtual-header` or `dashboard=xbe-executed`.
- The current focused Firefox BiDi browser-runtime diagnostic
  (`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-page-probe-combined.log`)
  now contains browser-runtime `xboxdash.xbe` read proof plus
  `dashboard=xbe-dma-buffer` and `dashboard=xbe-virtual-probe
  context=browser-runtime status=unmapped page_status=pde-not-present
  guest_addr=0x00010000 cr3=0x0000f000 pde_addr=0x0000f000
  pde=0x0000000000000000 guest_pc=0x80024307`. The native focused
  counterpart (`build-real-b3-matrix/native-60s-xbe-page-probe/boot-smoke.log`)
  reports the same `page_status=pde-not-present` boundary with
  `guest_pc=0x8001bd07`. The combined browser log correctly fails the B6
  loaded checker at `missing-xbe-loaded-marker`.
- The latest focused Firefox BiDi browser-runtime diagnostic
  (`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-read-progress-loaded-combined.log`)
  shows that the mapping appears on the next dashboard read:
  `dashboard=xbe-read-progress ... status=xbeh-present page_status=mapped-page
  phys_addr=0x000e0000`, followed by
  `dashboard=xbe-loaded context=browser-runtime guest_addr=0x00010000
  source=virtual-header`. The B6 checker now fails this combined log at
  `missing-xbe-executed-marker`, which is the current boundary. The native
  counterpart
  (`build-real-b3-matrix/native-60s-xbe-read-progress-loaded/boot-smoke.log`)
  also emits `dashboard=xbe-loaded context=native-headless` but no
  `dashboard=xbe-executed`.
- A newer native run after adding the TCG translated-block execution hook
  (`build-real-b3-matrix/native-60s-xbe-tcg-exec/boot-smoke.log`) still emits
  `dashboard=xbe-loaded context=native-headless` but no
  `dashboard=xbe-executed`. That keeps the active B6 blocker at execution
  observation or control-flow into the loaded dashboard XBE image range, not
  just browser-runtime behavior.
- The latest native exec-probe diagnostic
  (`build-real-b3-matrix/native-60s-xbe-exec-probe-cpu-context/boot-smoke.log`)
  includes high-alias physical verification and CPU-context fields in the
  execution detector, and emits periodic `dashboard=xbe-exec-probe` samples
  through `observed_tbs=310000`. The probe now logs `address_mode`,
  `guest_phys`, `image_phys`, `phys_match`, `cpu_mode`, `cpl`, segment
  selectors, registers, and control registers. Sampled high aliases that
  overlap the XBE virtual range map to different physical pages than the loaded
  dashboard image (`address_mode=high-alias-mismatch phys_match=no`), every
  sampled TB remains `cpu_mode=protected32 cpl=0 cs=0x0008`, and no
  `dashboard=xbe-executed` marker appears.
- The latest Firefox BiDi browser-runtime exec-probe diagnostic
  (`build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-probe-cpu-context-combined.log`)
  proves browser-runtime `xboxdash.xbe` read plus
  `dashboard=xbe-loaded context=browser-runtime`, emits
  `dashboard=xbe-exec-probe context=browser-runtime` with phys-map and
  CPU-context fields through `observed_tbs=200000`, and correctly fails the B6
  checker at `missing-xbe-executed-marker`. Early high-alias samples overlap the
  XBE virtual range while the image alias is not yet mapped; later samples are
  outside the dashboard XBE alias range. Every sampled browser TB also remains
  `cpu_mode=protected32 cpl=0 cs=0x0008`.
- The latest ret-target execution diagnostics add bounded code-site hashes,
  opcode/modrm fields, branch kind, and readable return/direct/register branch
  targets to `dashboard=xbe-exec-probe` without dumping raw code bytes. Native
  `build-real-b3-matrix/native-60s-xbe-exec-ret-target-probe/boot-smoke.log`
  shows sampled `ret` sites returning to `0x80030e84`; browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-ret-target-probe-combined.log`
  shows sampled returns targeting kernel high aliases such as `0x8001ae75` and
  `0x8001a429`. These targets remain `branch_relation=above` and do not
  physically match the loaded dashboard image. The browser combined log still
  proves `xboxdash.xbe` read/load and still fails the B6 checker at
  `missing-xbe-executed-marker`.
- The latest post-TB transition diagnostics add
  `dashboard=xbe-exec-transition` after translated blocks execute. Native
  `build-real-b3-matrix/native-60s-xbe-exec-transition-probe/boot-smoke.log`
  and browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-transition-probe-combined.log`
  sample the synchronized next PC and can emit `dashboard=xbe-executed` if that
  next PC reaches the loaded dashboard image. Current native next PCs still
  cycle through kernel locations such as `0x80030e84`, `0x80014f32`, and
  `0x800426d4`; browser next PCs still cycle through kernel locations such as
  `0x8002430e`, `0x8001ae75`, `0x80060ffe`, and `0x80014fb4`. No post-TB next
  PC physically matches the loaded dashboard image, and the browser combined
  log still fails the B6 checker at `missing-xbe-executed-marker`.
- The latest transition-edge diagnostics add bounded
  `dashboard=xbe-exec-edge` summaries after translated blocks. The native
  artifact is
  `build-real-b3-matrix/native-60s-xbe-exec-edge-probe/boot-smoke.log`, and the
  browser artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-exec-edge-probe-combined.log`.
  The browser run proves selected-assets runtime, browser-block B3, B4 display
  capture, `xboxdash.xbe` read, and `dashboard=xbe-loaded`, emits 64 edge
  samples, and still fails the B6 checker at
  `missing-xbe-executed-marker`. Repeated browser edges remain in
  kernel/high-alias paths such as `0x80014159 -> 0x80014386`,
  `0x8004cdb8 -> 0x80014fb4`, and `0x80014fb4 -> 0x8001aea5`; none physically
  match the loaded dashboard image.
- The latest branch-target diagnostics widen the retained edge cache to 64
  unique edge shapes and decode register plus memory-indirect `FF /2` and
  `FF /4` call/jmp operands in edge samples. Native
  `build-real-b3-matrix/native-60s-xbe-branch-target-classification/boot-smoke.log` and
  browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-branch-target-classification-combined.log`
  both resolve a memory-indirect `call-mem32` through operand address
  `0x8003ad24` to target `0x800241fe`; the browser wide-edge run also records
  `call-reg` dispatch to `0x80046280`. Transition and edge logs now add
  `next_branch_relation`, `next_branch_address_mode`, physical mapping fields,
  and `next_branch_phys_match` for decoded branch targets. The new browser log
  shows sampled branch targets are still kernel/high-alias targets
  (`next_branch_relation=above`, `next_branch_address_mode=high-alias-mismatch`
  or `none`, and no physical match to the loaded dashboard image), not
  dashboard XBE execution. The browser combined log proves browser-runtime
  `xboxdash.xbe` read, B4 display capture, B5 runtime evidence, and
  `dashboard=xbe-loaded`, but still fails the B6 checker at
  `missing-xbe-executed-marker`.
- The latest entry-point diagnostics prove the decoded dashboard entry becomes
  readable in both native and browser-runtime contexts. Native
  `build-real-b3-matrix/native-60s-xbe-entry-probe-v2/boot-smoke.log` and
  browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-probe-combined.log`
  both probe decoded dashboard entry `0x00017d60`, first emitting
  `dashboard=xbe-entry-probe ... status=unreadable` while the entry code is not
  mapped, then one `status=ready` marker with `entry_phys=0x000c7d60`,
  `entry_code_hash=0x7cbb4e8a328f1553`, and `entry_opcode=0x55`. The browser
  artifact passes B4 display capture, B5 runtime evidence, and browser-runtime
  `xboxdash.xbe` read correlation, but the combined log still fails the B6
  checker at `missing-xbe-executed-marker`. Entry readiness narrows the handoff
  window without completing B6.
- The latest entry-target diagnostics add bounded probes for branch targets
  near the decoded dashboard entry point. Native
  `build-real-b3-matrix/native-60s-xbe-entry-target-probe/boot-smoke.log` and
  browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-entry-target-probe-combined.log`
  both emit 16 `dashboard=xbe-entry-target-probe` markers. The browser artifact
  passes B4 display capture, B5 runtime evidence, and browser-runtime
  `xboxdash.xbe` read correlation, but still fails the B6 checker at
  `missing-xbe-executed-marker`. The sampled near-entry targets remain
  kernel/high-alias paths with `target_status=near-phys-unknown`, including
  ret-stack targets near `0x8001ae75` and call targets near `0x80018d30` or
  `0x800241fe`; none prove dispatch into the loaded dashboard image. The fresh
  target-hash-v1 browser artifact includes `target_code_hash` and
  `target_image_code_hash` on all 16 sampled entry-target markers, and the hash
  audit reports `target_disk_hash_match=0`, so decoded target bytes can be
  checked against the dashboard file without exposing proprietary bytes.
- The latest dispatch diagnostics inspect post-load register and top-stack
  candidates without dumping raw stack contents. Native
  `build-real-b3-matrix/native-60s-xbe-dispatch-probe-v3/boot-smoke.log` emits
  16 `dashboard=xbe-dispatch-probe` markers, and browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-xbe-dispatch-probe-v3-combined.log`
  emits 10. Both keep `reg_phys_match_count=0` and
  `reg_entry_near_count=0`; the browser probes keep `reg_first_candidate=none`
  throughout. The only native register candidate is a high-alias mismatch
  (`ecx=0x8003a950`) above the dashboard image, not execution. Stack direct
  matches, when present, point into XBE headers (`stack_first_in_headers=yes`);
  other stack candidates are high-alias mismatches or unknown physical mappings
  near kernel paths such as `0x8001ae75`, `0x8001a429`, and `0x800141bb`. The
  browser artifact passes B4 display capture, B5 runtime evidence, and
  browser-runtime `xboxdash.xbe` read correlation, but still fails the B6
  checker at `missing-xbe-executed-marker`.
- The latest PFIFO/NV2A/PGRAPH diagnostics add bounded `pfifo=progress`
  markers, divergence-window `pfifo=window` markers controlled by
  `XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_START` and
  `XEMU_BOOT_TRACE_NV2A_PFIFO_WINDOW_LIMIT`, bounded `pgraph=method` markers,
  divergence-window `pgraph=method-window` markers controlled by
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_START` and
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_METHOD_WINDOW_LIMIT`, bounded
  `pgraph=notify-error` markers controlled by
  `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_LIMIT`, bounded `pgraph=notify-clear`
  markers controlled by `XEMU_BOOT_TRACE_NV2A_PGRAPH_NOTIFY_CLEAR_LIMIT`,
  filtered `nv2a=irq-source` markers, bounded `nv2a=irq-line` markers, a
  separate non-priority IRQ-line cap controlled by
  `XEMU_BOOT_TRACE_NV2A_IRQ_LINE_LOW_PRIORITY_LIMIT`, earlier
  `nv2a=pmc-access` markers, and diagnostic-only `nv2a_wait_*` fields on
  kernel-loop probes. Native
  `build-real-b3-matrix/native-120s-command-window-null-flip-probe/boot-smoke.log`
  and browser
  `build-real-b3-matrix/browser-runtime-firefox-bidi-command-window-v2-combined.log`
  both still show post-load execution remains in kernel/high-alias paths, but
  now narrow the device-side gap beyond notify clearing and the late graphics
  command window. The null-renderer flip-stall mismatch is fixed: native and
  browser both continue past `NV097_FLIP_STALL`, consume the late command
  window through `NV097_SET_COLOR_CLEAR_VALUE`, and reach PFIFO empty with
  `dma_get=dma_put=0x03881318` and `waiting_flip=no`. The Firefox BiDi browser
  artifact passes B4 display capture, B5 runtime evidence, browser-runtime
  `xboxdash.xbe` read correlation, alias hash audit, entry-ready evidence, and
  command-stream alignment, but still fails the B6 checker at
  `missing-xbe-executed-marker`. The command-window comparator reports
  `command_stream_aligned=yes divergence=post-command-loop-mismatch`. The
  command-window post-command CPU/XBE handoff comparator reports both sides
  entry-ready and stream-idle, but `any_handoff_candidate=no`: no sampled native
  or browser execution probe or transition next-PC physically matches the loaded
  dashboard image. The command-window loop-cluster report adds ordering-aware
  after-idle fields: native still reaches PFIFO empty and then a post-idle
  loop with `pmc_enabled=0x00000001`, while that browser after-idle
  probes reach a different kernel/high-alias loop around
  `0x80044feb -> 0x80044fff`. That post-command IRQ/PMC comparator reports
  `divergence=browser-pmc-disabled-after-idle`: native keeps PMC enabled after
  an enable write from `eip=0x80046318`, while browser repeatedly disables
  `NV_PMC_INTR_EN_0` from `eip=0x80045ba1` and then samples the post-idle loop
  with `pmc_enabled=0x00000000` while PCRTC vblank raise/clear activity
  continues. That PCRTC vblank divergence helper reports
  `divergence=browser-initial-pcrtc-pending`: native has no PCRTC vblank raises
  in the paired headless log and all PMC disables are PGRAPH-driven, while the
  browser starts with `pcrtc_pending_before=0x00000001`, records 62 PCRTC
  vblank raises, and records 70 PCRTC-driven PMC disables. No run has produced
  a `dashboard=xbe-executed` marker.
- Browser-only PCRTC vblank cadence is now controllable for diagnostics with
  `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=normal|off|suppress-until-dashboard-observed|suppress-until-entry-ready`.
  The page/worker path writes the selected mode into the wasm fixture
  filesystem, so the C-side browser build does not rely only on host
  `getenv()` propagation. Non-normal modes emit sampled
  `BOOT_MARK b6 nv2a=pcrtc-vblank-gate ...` markers and are diagnostic only:
  they must not satisfy B6 without real `dashboard=xbe-executed` and native
  reference-frame match evidence.
- The focused Firefox BiDi run
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pcrtc-vblank-off-v1-combined.log`
  used `XEMU_BROWSER_BOOT_PCRTC_VBLANK_MODE=off`. It proves the diagnostic
  reached wasm, emits vblank-gate suppress markers, keeps B4 display capture
  and B5 runtime evidence, and still proves browser-runtime `xboxdash.xbe`
  read/load plus entry-ready evidence. Against
  `build-real-b3-matrix/native-120s-pmc-cpu-context-v1/boot-smoke.log`, the
  PCRTC comparator now reports `divergence=same-pcrtc-vblank-shape`, the
  PGRAPH comparator still reports `command_stream_aligned=yes`, and the IRQ/PMC
  comparator reports matching loop PMC pending/enabled state. The latest
  IRQ-watch serviceable idle-loop diagnostic
  `build-real-b3-matrix/browser-runtime-firefox-bidi-irq-watch-route-v3-combined.log`
  runs with `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=idle-loop-serviceable`
  and `XEMU_BOOT_TRACE_XBE_IRQ_WATCH=6,12`.
  It proves browser-runtime `xboxdash.xbe` read/load/entry-ready, keeps B4/B5
  evidence, and moves the first browser hard IRQ to the same serviceable idle
  PC as native, `0x8001b030`, with interrupts enabled and no IRQ inhibition.
  It still emits no `dashboard=xbe-executed` marker, so B6 remains incomplete.
  The remaining divergence is post-idle CPU flow:
  `scripts/xbox-post-idle-interrupt-flow-compare.py` reports
  `divergence=browser-extra-interrupt-vector` with
  `browser_extra_pic_line_assert_irqs=12,6`,
  `browser_extra_lpc_route_assert_irqs=12,6`, and
  `browser_extra_pic_ack_vectors=0x3c,0x36`; the first vector `0x30` service
  reaches handler PC `0x80030e4c` in both native and browser, but browser then
  asserts/routes extra IRQs and records a different first post-service loop
  edge. The native reference
  `build-real-b3-matrix/native-120s-irq-watch-route-v1/boot-smoke.log` shows
  native PIC ack sampling stays on vector `0x30` and has no matching LPC route
  or PIC line assertion. The browser source markers show `0x3c` is ACPI PM
  routed to guest IRQ 12 through slave IRQ 4, while `0x36` is MCPX ACI routed
  to master IRQ 6. Both assertions occur at `eip=0x8001b030` after PFIFO
  reaches pusher-empty.
- The timer-pump attribution diagnostic
  `build-real-b3-matrix/browser-runtime-firefox-bidi-timer-pump-attribution-v2.log`
  is diagnostic-only because it times out and lacks the full combined B6 read
  evidence, but it proves the browser-only PM/AC97 source events fire inside
  the browser TCG-side virtual timer pump: the comparator reports
  `browser_pm_timer_pump_active_events=1`,
  `browser_ac97_callback_pump_active_events=9`,
  `browser_ac97_transfer_pump_active_events=1`, and
  `browser_ac97_irq_pump_active_events=1`, while guest cleanup writes such as
  PM event writes and AC97 bus-master writes are pump-inactive. The next
  technical slice is therefore to make browser timer progression match the
  native main-loop timer boundary, or filter the diagnostic pump so it does not
  run unrelated PM timer and AC97 playback callbacks while trying to deliver
  the native PIT service point. This must remain diagnostic-only until it
  produces real `dashboard=xbe-executed` evidence.
- The PIT-only timer-pump diagnostic
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-only-pump-v1.log` adds
  `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=idle-loop-serviceable-pit-only`,
  tags the PIT timer as pump-eligible, and filters the browser pump to that
  timer. Native and wasm builds passed with this change. The focused comparator
  reports `browser_extra_vectors=none`, `browser_extra_pic_ack_vectors=none`,
  no extra PIC/LPC assertions, and zero PM/AC97 callback/source events, while
  the first hard-IRQ service and first IRET match native. This artifact still
  times out and is diagnostic-only, but it moves the live B6 boundary from
  PM/AC97 timer-pump noise to CPU-flow parity after the native-matching
  PIT/vector `0x30` service.
- The post-idle PIT-gate diagnostics
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-pump-v1.log`
  and
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-pump-v1.log`
  add `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_MODE=pit-after-idle` and
  `pit-after-idle-full`. The full-idle mode waits for the complete
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT` sample budget before the
  PIT-only pump. It still times out without `dashboard=xbe-executed`, but the
  comparator keeps `browser_extra_vectors=none`, preserves native-matching
  first hard-IRQ service plus first IRET, and removes the earlier
  browser-only first post-service loop (`browser_first_post_service_loop=none`).
  The remaining mismatch is at the PFIFO stream-idle boundary: native's first
  stream-idle loop sample starts `0x8001b030 -> 0x8001b02f`, while browser's
  first stream-idle loop sample starts `0x8001b02f -> 0x8001b030`.
- The PFIFO stream-idle boundary diagnostic adds a bounded
  `BOOT_MARK b6 pfifo=stream-idle-boundary ...` marker at the first PFIFO
  `pusher-empty` snapshot and compares native/browser CPU context plus the
  latest translated-block transition with
  `scripts/xbox-pfifo-stream-idle-boundary-compare.py`. Native and wasm builds
  passed with this change. The fresh artifacts are
  `build-real-b3-matrix/native-pfifo-boundary-v1/boot-smoke.log` and
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-boundary-pit-after-idle-full-v1.log`.
  The comparator reports `divergence=boundary-cpu-state-mismatch`: native's
  first PFIFO-empty boundary is at `eip=0x80042910` with last transition
  `0x800426de -> 0x80042910`, while browser's first PFIFO-empty boundary is
  already at `eip=0x8001b030` with last transition
  `0x8001b030 -> 0x8001b02f`. The browser runtime still times out and emits no
  `dashboard=xbe-executed`, so this remains diagnostic-only evidence.
- The PFIFO stream-idle transition diagnostic adds a bounded
  `BOOT_MARK b6 pfifo=stream-idle-transition ...` marker at the final
  `DMA_GET` commit into empty, before the later `pusher-empty` boundary. Fresh
  artifacts are `build-real-b3-matrix/native-pfifo-activity-v1/boot-smoke.log`
  and
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-activity-v1.log`.
  Native and wasm builds passed with this change, and both sides emit the
  marker for the same final command: `dma_get_before=0x03881314`,
  `dma_get_after=0x03881318`, `dma_put=0x03881318`, `method=0x1d90`, and
  `processed=1`. The comparator reports
  `divergence=transition-cpu-state-mismatch`: native and browser commit the
  same final PFIFO command from the same CPU edge, but native has
  `cpu_interrupt_request=0x00000002` while browser has
  `cpu_interrupt_request=0x00000000`. This remains diagnostic-only evidence
  because the browser runtime still times out and emits no
  `dashboard=xbe-executed`.
- The `pit-after-pfifo-transition` diagnostic adds a focused browser timer-pump
  mode that waits until the exact `pfifo=stream-idle-transition` marker before
  allowing the PIT-only pump. The fresh artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-transition-pit-at-transition-v1.log`.
  It still times out without `dashboard=xbe-executed`, but it proves this later
  gate is not enough: PM/AC97 noise and extra vectors stay absent, yet browser
  still reaches the transition without the native pending hard IRQ and sets it
  later from the TCG-side timer pump. The next slice is IRQ/timer scheduling at
  the final PFIFO transition, not more PIT pump timing.
- The `pit-before-pfifo-transition` gate diagnostic adds
  `BOOT_MARK b6 tcg=timer-pump-gate ...`, controlled by
  `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_GATE_LIMIT`. The focused gate-only
  artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-v3.log`.
  It proves the idle-PC-only pre-transition gate can miss the last command
  window when the browser reaches the near-final PFIFO activity while the CPU is
  still at `0x800426de`.
- The `pit-before-pfifo-transition-activity` diagnostic loosens the
  pre-transition gate to near-final PFIFO activity and remains PIT-only. The
  focused artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-before-transition-activity-v1.log`.
  It proves the early activity gate is also not the fix: the pump sets
  `CPU_INTERRUPT_HARD` before PFIFO empties, but the browser CPU accepts vector
  `0x30` and reaches handler PC `0x80030e4c` before the final
  `pfifo=stream-idle-transition`. The remaining ordering target is between the
  too-late post-transition pump and the too-early activity-gated pump: match
  native's state where the IRQ is pending at the final PFIFO commit and is
  serviced after that commit.
- The `pit-before-pfifo-transition-activity-defer-to-idle` diagnostic defers
  hard-IRQ service after the PIT pump until the browser reaches the native
  serviceable idle PC. The fresh artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-defer-to-idle-v1.log`.
  Native and wasm builds passed, and the browser runtime still passes B5 while
  timing out without `dashboard=xbe-executed`. This run proves useful progress:
  browser keeps `CPU_INTERRUPT_HARD` pending through the post-PFIFO handoff and
  services vector `0x30` at `eip=0x8001b030`, with the same service/IRET frame
  hash as native. It still does not satisfy B6. The remaining mismatch is
  earlier than hard-IRQ service: native already has `CPU_INTERRUPT_HARD` pending
  at the final PFIFO transition, while browser sets it later from the TCG-side
  PIT pump.
- The `pit-at-pfifo-transition-pre-commit-defer-to-idle` diagnostic runs a
  one-shot PIT-only pump at the final PFIFO DMA GET pre-commit point, taking BQL
  for the PIT callback and reacquiring the PFIFO lock before the pusher commits
  the final `DMA_GET`. The fresh artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-pre-commit-pit-v2.log`.
  Native and wasm builds passed. The first attempt without BQL correctly
  aborted at `cpu_interrupt: assertion failed: (bql_locked())`, proving the
  PIT callback must run under BQL; the v2 artifact fixes that. This is still
  diagnostic-only and times out without `dashboard=xbe-executed`, but it moves
  the boundary forward: browser now reaches the final
  `pfifo=stream-idle-transition` with `cpu_interrupt_request=0x00000002`
  pending, matching native's pending hard IRQ at that point. The browser also
  services vector `0x30` at `0x8001b030`, and the first service/IRET frame hash
  still matches native. The remaining mismatch is now after the first service:
  browser records a post-service loop edge `0x80030e4c -> 0x80014f2d`, while
  the compact native reference flow records the IRET marker first and continues
  through repeated PIT vector `0x30` services.
- The idle-before-PFIFO-transition diagnostic adds
  `BOOT_MARK b6 cpu=idle-before-pfifo-transition ...`, controlled by
  `XEMU_BOOT_TRACE_XBE_IDLE_BEFORE_PFIFO_TRANSITION_LIMIT`, and the helper
  `scripts/xbox-idle-before-pfifo-transition-compare.py`. The focused artifacts
  are
  `build-real-b3-matrix/native-pfifo-activity-v1/boot-smoke.log`
  and
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pfifo-activity-v1.log`.
  The comparator now reports both markers present with
  `divergence=idle-before-transition-mismatch`, superseding the older
  `browser-idle-before-transition-only` result. Native and browser both reach
  the same idle edge, `0x8001b02e -> 0x8001b02f`, while PFIFO still has
  `dma_get=0x0388130c`, `dma_put=0x03881318`, and 12 bytes left to consume.
  The diagnostic PFIFO activity snapshot also aligns:
  `pfifo_activity_phase=puller-method-pgraph-return`,
  `pfifo_activity_pfifo_lock_released=yes`,
  `pfifo_activity_pgraph_locked=yes`, and
  `pfifo_activity_final_transition_candidate=no`. This rules out a
  PFIFO/PGRAPH activity-phase mismatch for the older `pfifo-activity-v1`
  baseline artifact. In that baseline, the split is hard-IRQ/timer scheduling at
  the following stream-idle transition: native has `CPU_INTERRUPT_HARD` pending
  at the final PFIFO command commit, while browser does not until later
  TCG-side timer pumping. The newer PFIFO pre-commit PIT artifact moves past
  that specific split and leaves post-service loop flow as the front-most
  diagnostic mismatch.
- The PFIFO-transition IRQ timing diagnostic adds
  `scripts/xbox-pfifo-transition-irq-timing.py`, which summarizes the first
  PIT/timer, hard-IRQ set/reset, PIC ack, and hard-IRQ service markers around
  the final `pfifo=stream-idle-transition`. On the current `pfifo-activity-v1`
  logs it reports `divergence=transition-pending-irq-mismatch`: native reaches
  the transition with `native_transition_irq=0x00000002`, while browser reaches
  it with `browser_transition_irq=0x00000000`; browser's first hard-IRQ set
  happens later after the `tcg=timer-pump` marker. This helper is
  diagnostic-only and must not satisfy B6.
- The fresh native post-IRET flow reference is
  `build-real-b3-matrix/native-post-iret-flow-v1/boot-smoke.log`. It extends
  the native after-idle loop budget to 128 samples and records repeated PIT
  vector `0x30` service after PFIFO pusher-empty. Compared with the useful
  browser PFIFO-empty artifact
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-pump-timeout-300s-v1-combined.log`,
  `scripts/xbox-iret-frame-compare.py` reports `divergence=none`: native and
  browser have the same preferred handler PC `0x80030e4c`, return PC
  `0x8001b030`, IRET-after ESP `0x800395f0`, flags, and stack hash
  `0x455d94af83816994`. `scripts/xbox-post-command-loop-clusters.py` now
  reports `browser_stream_idle_seen=yes`, `after_idle_divergence=edge-mismatch`,
  and `after_idle_cpu_interrupt_divergence=native-only-after-idle-cpu-interrupt`
  for that pair.
  This was an older front-most B6 split: the useful browser artifact matches
  the native interrupt-return frame and reaches PFIFO pusher-empty with combined
  dashboard read/load/entry-ready evidence, but does not produce the matching
  after-idle CPU interrupt evidence and still does not emit
  `dashboard=xbe-executed`.
- The browser harness now forwards diagnostic kernel-loop controls into the
  wasm fixture filesystem:
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_LIMIT`,
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT`, and
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_MIN_HITS`. The C-side probe reads those
  fixture settings in browser runs. This is long-term useful, but the focused
  v4 run
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v4.log`
  is a negative diagnostic: it passes browser runtime evidence again, but does
  not reach PFIFO stream-idle and the comparators report browser
  `stream_idle_seen=no`, `browser-no-after-idle-loop-samples`, and
  `command-stream-not-idle`. Keep
  `pit-after-idle-full-pump-v1.log` as the useful PFIFO-empty browser
  reference until the trace controls can enlarge only the after-idle window
  without re-sampling earlier PGRAPH interrupt-enable wait state.
- The next trace-control fix now separates the after-idle kernel-loop sample
  budget from the browser PIT-pump after-idle gate. Keep
  `XEMU_BOOT_TRACE_XBE_KERNEL_LOOP_AFTER_IDLE_LIMIT` for sample/logging budget,
  and use `XEMU_BOOT_TRACE_XBE_TCG_TIMER_PUMP_AFTER_IDLE_LIMIT` for the
  `idle-loop-serviceable-pit-after-idle-full` pump threshold. The focused v5
  run
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5.log`
  passes B4 display capture and B5 browser runtime evidence, proves partial
  browser-runtime dashboard XBE read/load/entry-ready progress, and the
  combined v5 artifact
  `build-real-b3-matrix/browser-runtime-firefox-bidi-pit-after-idle-full-post-iret-v5-combined.log`
  appends FATX/IDE read evidence with
  `scripts/xbox-combine-dashboard-xbe-read-evidence.sh`. The raw C
  read-progress marker reports `contiguous_bytes=172032` versus
  `image_size=175080`; the FATX correlator proves `xboxdash.xbe` file size is
  `172032`, while `image_size` is the XBE in-memory image size. The combined
  log therefore passes the read/load/entry-ready side and correctly fails the
  B6 checker at `missing-xbe-executed-marker`. It still has no browser PFIFO
  stream-idle and no native visual-reference match. Treat this as forward
  progress on the B6 evidence boundary, not completion.
- The stable B5-pass/read-proof browser artifact is
  `build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log`.
  It uses rebuilt wasm with XBE section-map diagnostics and appends FATX/IDE
  dashboard-read proof with `scripts/xbox-combine-dashboard-xbe-read-evidence.sh`.
  It passes B5 browser runtime evidence, passes B4 display capture evidence,
  proves browser-runtime `xboxdash.xbe` read/load/entry-ready, emits
  `dashboard=xbe-section-map phase=entry-ready`, maps executable entry section 3
  from entry `0x00017d60` to `entry_phys=0x000c7d60`, and matches the native
  preferred vector `0x30` service/IRET frame. It supersedes the older 300s,
  `pit-after-idle-full-pump-v1.log`, and v5 combined logs as the B5-pass
  dashboard-read baseline. It still does not complete B6 because
  `scripts/xbox-dashboard-loaded-evidence-check.sh` correctly fails it at
  `missing-xbe-executed-marker`; native dashboard reference capture and
  browser-vs-native visual comparison remain blocked on real browser-runtime
  `dashboard=xbe-executed`. Validate the section-map diagnostic with
  `scripts/xbox-dashboard-section-map-evidence-check.sh build-real-b3-matrix/browser-runtime-firefox-bidi-section-map-v2-combined.log`.
  These markers are metadata-only and must not satisfy B6 without
  browser-runtime `dashboard=xbe-executed` plus native/browser dashboard
  visual-match evidence.
  The `dashboard=xbe-executed` marker is intentionally strict: it must carry
  `phys_match=yes` and executable section metadata (`section_flags` containing
  `0x4`), and `scripts/xbox-dashboard-loaded-evidence-check.sh` rejects weaker
  executed markers.

Historical B6 work queue snapshot:

The current next actions, loop guards, and active artifact roles live in
`goal.md`. The notes below are historical context and should not override
`goal.md`.

1. Finish the browser dashboard XBE execution proof. The section-map v2 combined
   browser diagnostic reaches `dashboard=xbe-loaded`, an
   entry-ready probe, an entry-ready section map, and browser-runtime FATX
   `xboxdash.xbe` read evidence while preserving B4/B5 evidence. The current
   checker failure is `missing-xbe-executed-marker`, not a read/load/runtime
   failure. Continue using the section-map diagnostic to describe the loaded XBE
   ranges and physical mappings, but do not treat it as dashboard execution.
   The execution question remains: post-load execution stays in
   protected-mode kernel TBs (`cpl=0 cs=0x0008`) after the dashboard XBE has
   been mapped, loaded, and its decoded entry point has become readable. Start
   from the PGRAPH PMC CPU-context and command-window probe logs plus the
   dispatch,
   entry-target, branch-target,
   alias hash audit, and earlier memclass kernel-loop logs. PFIFO and PGRAPH
   method progress now appears aligned in both native and browser, the stale
   PGRAPH aggregate interrupt bit is fixed, both native and browser
   notify-clear probes prove the notify wait state clears, and both sides now
   reach PFIFO empty after the late command window. The PCRTC-off diagnostic
   removes the browser-only vblank cadence as the immediate mismatch and leaves
   matching loop PMC pending/enabled state, but it still does not produce
   dashboard execution proof. The later serviceable idle-loop, PIT-only, and
   post-idle PIT-gate artifacts progressively removed the older PM/AC97 noise,
   extra vectors, transition pending-IRQ mismatch, and first IRET-frame
   mismatch. The fresh native post-IRET reference plus the useful browser
   `pit-after-idle-full-pump-v1` artifact now shows the preferred vector `0x30`
   service/IRET frame and the after-idle top loop edge match. The next anchor is
   narrower: native records after-idle CPU interrupt samples after PFIFO empty,
   while browser does not, and neither side reaches physically matching
   dashboard XBE execution. Use
   `scripts/xbox-post-command-handoff-compare.py` on the paired native/browser
   command-window logs to summarize whether any execution or transition probe
   has become a physical dashboard-image match, and
   `scripts/xbox-post-command-loop-clusters.py` to summarize native/browser loop
   shapes, wait sources, and whether loop samples were captured after PFIFO
   empty. Use `scripts/xbox-post-idle-interrupt-flow-compare.py` to summarize
   vector, IRET, and post-service edge flow, then use
   `scripts/xbox-post-command-irq-state-compare.py` and
   `scripts/xbox-pcrtc-vblank-divergence.py` to summarize the post-idle NV2A
   PMC/PCRTC divergence before changing renderer or dashboard completion logic.
   The PIT-only timer-pump diagnostic now isolates that pump to the tagged PIT
   timer and removes the browser-only PM/AC97 assertions without losing the
   native-matching PIT/vector `0x30` service. The full post-idle PIT-gate
   diagnostic also removes the earlier first post-service loop symptom. The
   `pit-after-pfifo-transition` diagnostic proves that waiting until the final
   PFIFO transition before pumping PIT removes PM/AC97 noise and extra vectors,
   but browser still sets the hard IRQ later instead of matching native's
   pending-hard-IRQ transition state. The activity-gated pre-transition
   diagnostic proves the opposite side of the boundary: pumping at
   `puller-method-pgraph-call` is too early because the browser services vector
   `0x30` before the final PFIFO commit. The defer-to-idle diagnostic removes
   the older first-service-frame mismatch by holding the pending hard IRQ until
   `0x8001b030`; its first service and IRET frame now match native. The PFIFO
   pre-commit PIT diagnostic then removes the pending-hard-IRQ transition
   mismatch itself: browser and native now both have `CPU_INTERRUPT_HARD`
   pending at the final `pfifo=stream-idle-transition`, and the first vector
   `0x30` service frame still matches. The remaining technical slice is now
   after-idle CPU interrupt progress after the first matching service: explain
   why native records post-idle CPU interrupt samples and repeated PIT vector
   `0x30` services while the useful browser artifact has no after-idle CPU
   interrupt samples and times out without `dashboard=xbe-executed`. Native and
   browser are already aligned
   at `puller-method-pgraph-return`, at the final PFIFO transition's pending
   IRQ state, and at the first service frame, so do not fall back to another
   generic PFIFO/PGRAPH phase check, generic timer-pump mode, or renderer issue
   unless fresh evidence moves this boundary. Use
   `scripts/xbox-pfifo-transition-irq-timing.py` plus
   `scripts/xbox-post-idle-interrupt-flow-compare.py` on the PFIFO activity,
   pre-transition activity, defer-to-idle, and pre-commit PIT logs as the
   compact pass/fail summary for that boundary. Do not repeat the v4 larger
   early kernel-loop sampling run as the next step; it re-samples earlier PGRAPH
   interrupt-enable wait state and misses PFIFO stream-idle.
2. Preserve the standard real matrix with
   `XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi`; it is now the baseline
   combined log containing browser-runtime `xboxdash.xbe` read proof.
3. Keep Playwright as the preferred screenshot/canvas/reference-frame tooling,
   using `XEMU_BROWSER_RUNTIME_BROWSER=chromium|firefox` to select engines.
4. Keep Firefox BiDi as the long browser-runtime probe until Playwright Firefox
   reaches comparable B4/IDE-read evidence.
5. Treat
   `dashboard=xbe-header-resident source=physical-scan`,
   `dashboard=xbe-dma-buffer source=ide-dma-buffer`,
   `dashboard=xbe-virtual-probe source=virtual-probe`, and
   `dashboard=xbe-read-progress source=ide-dma-read-progress`,
   `dashboard=xbe-exec-probe source=tcg-tb`, and
   `dashboard=xbe-exec-transition source=tcg-tb-post`, and
   `dashboard=xbe-exec-edge`, `dashboard=xbe-alias-compare`,
   `dashboard=xbe-entry-probe`,
   `dashboard=xbe-entry-target-probe`,
   `dashboard=xbe-dispatch-probe`, and
   `dashboard=kernel-loop-probe`, `nv2a=pmc-access`, `nv2a=irq-source`,
   `nv2a=irq-line`, `pfifo=progress`, `pfifo=stream-idle-transition`,
   `pfifo=stream-idle-boundary`, `pgraph=method`,
   `pgraph=notify-error`, `pgraph=notify-clear`, and the `nv2a_wait_*` fields on
   `dashboard=kernel-loop-probe` as diagnostic hints only.
6. Add native reference-frame capture and browser-vs-native frame comparison
   that emits `BROWSER_DASHBOARD_CAPTURE result=pass native_ref_match=yes ...`.

## Browser Automation Tooling

Preferred stack for visual/dashboard evidence:

```sh
hash -r
export PATH="$HOME/.npm-global/bin:$PATH"
export NODE_PATH="$(npm root -g)"
node -e 'require("playwright"); console.log("playwright ok")'
```

Then run browser tests normally. On this machine Playwright is installed
globally under `$HOME/.npm-global/lib/node_modules`, so `NODE_PATH` is needed
for repo scripts that use `require("playwright")`. If the npm-global PATH was
added to a shell startup file after the current terminal opened, run
`source ~/.profile` or open a fresh shell before using the shorter interactive
commands. Playwright browser binaries are installed in `~/.cache/ms-playwright`.

Verified local sanity check on 2026-06-28 with the explicit unattended env
prefix below: Node `v22.22.2`, npm `10.9.7`, global Playwright `1.61.1`, and
browser binaries:

- Chromium: `$HOME/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome`
- Firefox: `$HOME/.cache/ms-playwright/firefox-1532/firefox/firefox`
- WebKit: `$HOME/.cache/ms-playwright/webkit-2311/pw_run.sh`

Other verified local tools: Firefox `140.11.0esr`, Python `3.12.13`,
`qemu-img` `10.1.0`, and Podman `5.8.2` through
`/tmp/xemu-podman-wrapper/docker`.

For unattended commands, avoid depending on shell startup files and prefix the
command explicitly:

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
NODE_PATH=$HOME/.npm-global/lib/node_modules \
<command>
```

Browser wasm C-side `getenv()` does not reliably receive host
`XEMU_BOOT_TRACE_*` values from the surrounding smoke command. For C-side
browser diagnostics, prefer browser-specific compiled defaults or add explicit
JS-to-wasm env plumbing before assuming a host env limit took effect.

The local Docker command may be provided by the Podman wrapper at
`/tmp/xemu-podman-wrapper/docker`. If synthetic matrix commands report
`docker: command not found`, run:

```sh
export PATH="/tmp/xemu-podman-wrapper:$PATH"
```

Automation order:

1. Use Playwright for new screenshot, canvas, and reference-frame tests; select
   the engine with `XEMU_BROWSER_RUNTIME_BROWSER=chromium` or `firefox`.
2. Keep the existing Firefox BiDi scripts as fallback when Playwright is
   missing, `NODE_PATH` is not configured, or Playwright engine progress lags
   the BiDi evidence.
3. For current long real-matrix browser-runtime probes, force the practical
   Firefox BiDi path with
   `XEMU_REAL_B3_BROWSER_RUNTIME_DRIVER=firefox-bidi scripts/xbox-real-b3-matrix.sh`.
4. Keep browser tests deterministic: write transcripts, frame hashes,
   screenshots, and explicit `BOOT_MARK`/`BROWSER_*` evidence lines.

Current local fixture exports for this machine:

```sh
export XEMU_MCPX='/home/sammy/Downloads/xemu/boot-rom-image/Boot ROM Image/mcpx_1.0.bin'
export XEMU_FLASH='/home/sammy/Downloads/xemu/complex-4627v1.03/Complex_4627v1.03.bin'
export XEMU_EEPROM=/tmp/xemu-b6-eeprom.bin
export XEMU_HDD='/home/sammy/Downloads/xemu/hard-disk-image/XBOX HDD/XBOX_HDD.qcow2/xbox_hdd.qcow2'
```

The user-supplied EEPROM source is
`/home/sammy/.local/share/xemu/xemu/eeprom.bin`; current B6 smoke commands use
the `/tmp/xemu-b6-eeprom.bin` copy to keep unattended runs isolated.

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
