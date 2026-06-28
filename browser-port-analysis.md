# Browser Port Analysis

This is a feasibility assessment for porting xemu to run in a web browser as a WebAssembly application. The short conclusion is that a browser port is technically possible as an experiment, but a playable in-browser xemu is a large research project rather than a straightforward Emscripten build.

## Current State

The codebase already has some WebAssembly scaffolding:

- `emscripten` and `wasm32` are recognized host targets in `meson.build`.
- There is an Emscripten coroutine backend in `util/coroutine-wasm.c`.
- `os-wasm.c` provides a reduced host OS layer.
- `configs/meson/emscripten.txt` contains wasm link settings including pthreads, Asyncify, `PROXY_TO_PTHREAD`, `FORCE_FILESYSTEM`, `TOTAL_MEMORY=2GB`, `WASM_BIGINT`, and ES module output.

That said, the normal product build is still a native SDL/OpenGL app. `build.sh` targets `qemu-system-i386` / `qemu-system-i386w.exe` and packages native Linux, macOS, and Windows builds. There is no browser packaging path today.

## Primary Blockers

### CPU Execution

This is the biggest blocker.

For WebAssembly hosts, `meson.build` explicitly requires `--enable-tcg-interpreter`. There is no wasm TCG code generator in `tcg/`; wasm falls back to TCI.

Relevant code:

- `meson.build`: WebAssembly host requires `--enable-tcg-interpreter`.
- `meson.build`: when `tcg_interpreter` is enabled, `tcg_arch = 'tci'`.
- `tcg/`: contains native TCG backends for architectures such as i386, arm, aarch64, riscv, ppc, and the `tci` interpreter, but no wasm code generator.

This likely makes full-speed original Xbox emulation in-browser impractical without a new CPU execution strategy. TCI may be enough for a smoke test or slow boot experiment, but not a compelling playable emulator.

### Graphics

The current UI and renderer are desktop OpenGL oriented:

- `ui/xemu.c` requests an OpenGL 4.0 core context.
- `ui/xemu.c` rejects GL versions below 4.0.
- The HUD uses ImGui with SDL3 and OpenGL bindings.
- The NV2A OpenGL renderer uses desktop GL features, generated GLSL `#version 400`, geometry shaders, and extensions such as S3TC.
- The Vulkan renderer exists, but browsers expose WebGPU, not Vulkan directly.

Trying to force the desktop OpenGL renderer through Emscripten's WebGL shim is probably the wrong first move. WebGL 2 is closer to OpenGL ES 3 than desktop OpenGL 4.0. A serious browser renderer likely needs a separate WebGPU backend or a major WebGL-specific rewrite.

### Threading

xemu is heavily native-threaded:

- `ui/xemu.c` creates the QEMU main thread.
- `ui/xemu.c` creates a vblank timer thread.
- `hw/xbox/nv2a/nv2a.c` creates the NV2A PFIFO thread.
- `hw/xbox/mcpx/apu/apu.c` creates the MCPX APU frame thread.
- `hw/xbox/mcpx/apu/vp/vp.c` creates voice worker threads.
- `hw/xbox/nv2a/pgraph/gl/shaders.c` creates shader cache worker threads.

Browser pthreads are possible with Emscripten, but require `SharedArrayBuffer` and cross-origin isolation headers. That means the browser build must be served from a secure context with COOP/COEP configured. This is manageable for an experiment, but it affects deployment and local dev setup.

### Storage And User Files

xemu expects real filesystem paths for:

- Flash BIOS.
- Optional boot ROM.
- Generated and persistent EEPROM.
- HDD image.
- DVD image.
- Config file.
- Shader cache.
- Snapshots and screenshots.

Relevant code:

- `system/vl.c` validates and passes BIOS/HDD/DVD/EEPROM paths into QEMU.
- `config_spec.yml` defines `sys.files.bootrom_path`, `flashrom_path`, `eeprom_path`, `hdd_path`, and `dvd_path`.
- `ui/xemu-settings.cc` uses SDL filesystem paths for config persistence.
- `hw/xbox/nv2a/pgraph/gl/shaders.c` writes shader cache files to disk.

In a browser, small files can be mounted into Emscripten FS, and persistent files can use IDBFS/OPFS-style storage. HDD and DVD images are the hard part: loading large images entirely into wasm memory is not viable. A useful browser port needs a block backend that can do random access over browser storage APIs or chunked user-provided files.

### Networking

xemu supports NAT, UDP, and PCAP-style network backends. Browsers do not expose raw UDP or PCAP. Practical browser networking would start disabled, then later use a WebSocket or WebRTC gateway if needed.

Relevant code:

- `ui/xemu-net.c` creates `user`, `socket`, or `pcap` netdevs.
- `config_spec.yml` defines `net.backend` values of `nat`, `udp`, and `pcap`.
- `hw/xbox/mcpx/nvnet/nvnet.c` implements the emulated nForce Ethernet controller.

## Build-System Issues To Fix First

The repository supports `emscripten` as a host in some places, but the product build is not wasm-ready.

Notable issues:

- `meson.build` still errors on unknown GL platforms for non-Linux, non-macOS, and non-Windows hosts.
- `epoxy` is required unconditionally.
- `libpcap` is required outside Windows.
- `libsamplerate` is required unconditionally.
- The xemu UI source set pulls SDL3, OpenGL, ImGui, ImPlot, stb_image, fpng, TOML, JSON, and generated config support.
- The NV2A null renderer's Meson stanza currently adds `sdl`, although the null renderer source itself does not appear to require SDL.

This means the first successful wasm build should probably be a deliberately reduced profile, not the full desktop xemu target.

## Recommended Experiment Path

### Phase 1: Headless Wasm Smoke Test

Goal: prove that the machine can initialize and run some amount of emulation loop in wasm.

Suggested constraints:

- Target `i386-softmmu`.
- Enable `--enable-tcg-interpreter`.
- Use the null NV2A renderer.
- Disable audio output.
- Disable networking.
- Avoid desktop `-display xemu`.
- Avoid SDL window creation.
- Mount BIOS/EEPROM/HDD/DVD through a simple Emscripten filesystem path first.

This phase will expose real compile and runtime blockers without committing to a renderer rewrite.

### Phase 2: Browser Host Shell

Goal: make the wasm build usable enough to configure and launch.

Needed pieces:

- HTML/JS host page.
- File pickers for BIOS, HDD, and DVD.
- Persistent config and EEPROM storage.
- Log console.
- Explicit browser capability checks for SharedArrayBuffer, WebAssembly threads, and storage.
- A reproducible local dev server with COOP/COEP headers.

### Phase 3: Minimal Display Path

Goal: show frames in a browser canvas.

Options:

- Software or framebuffer-only display first.
- Then WebGL 2 if a reduced path is possible.
- Prefer WebGPU for a long-term NV2A renderer experiment.

This should avoid trying to port the entire existing OpenGL 4.0 renderer unchanged.

### Phase 4: Browser Audio

Goal: connect the MCPX APU output to browser audio.

Likely approach:

- Use an AudioWorklet-backed output path.
- Keep noaudio as the initial default.
- Add buffering and latency controls later.

### Phase 5: Performance Work

Goal: determine whether playable browser xemu is realistic.

The key question is CPU execution. If TCI is too slow, the project needs one of:

- A wasm-native TCG backend.
- A separate x86-to-wasm translation strategy.
- A split architecture where CPU emulation runs somewhere else.
- A server-side xemu streaming design instead of fully local browser emulation.

## Porting Paths

### Path A: Headless Proof Of Concept

This is the best first experiment.

Pros:

- Smallest change set.
- Validates Emscripten build plumbing.
- Validates wasm memory/thread assumptions.
- Avoids graphics complexity.

Cons:

- Not playable.
- May only prove that TCI is too slow.

### Path B: Local Browser Emulation

This is the full ambitious port.

Pros:

- Most interesting result.
- Runs locally in the browser with no server-side emulation.

Cons:

- Requires CPU, GPU, storage, audio, input, and threading work.
- Performance risk is high.
- Browser deployment needs cross-origin isolation.

### Path C: Server-Side xemu Streamed To Browser

This is the fastest route to "xemu in a browser" from a user experience perspective.

Pros:

- Reuses native xemu.
- Avoids wasm CPU and WebGPU renderer risk.
- Can be playable much sooner.

Cons:

- Not a true browser port.
- Requires server infrastructure.
- Input latency and streaming quality become the main issues.

## Feasibility Verdict

- Headless wasm init: plausible.
- Boot firmware/dashboard in browser: possible, but significant.
- Play games with graphics/audio: large project.
- Full-speed playable browser xemu: unlikely without a new CPU execution strategy and browser-native GPU backend.

The most useful next step is a wasm/null-renderer smoke test. If that cannot run at an acceptable baseline speed, a full local browser port is probably not worth pursuing until CPU execution has a better answer.

## External References

- Emscripten pthreads: https://emscripten.org/docs/porting/pthreads.html
- Emscripten filesystem overview: https://emscripten.org/docs/porting/files/file_systems_overview.html
- Emscripten OpenGL support: https://emscripten.org/docs/porting/multimedia_and_graphics/OpenGL-support.html
- Emscripten networking: https://emscripten.org/docs/porting/networking.html
- MDN SharedArrayBuffer: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer
- MDN WebGPU API: https://developer.mozilla.org/en-US/docs/Web/API/WebGPU_API
