# Agent Notes

## Current Project Direction

This branch is focused on making xemu run in a browser through WebAssembly.
The practical target is an Xbox boot flow in the browser that can reach the
main menu/dashboard and eventually load a game.

Treat the browser work as an emulator-porting problem first, not a UI polish
problem. The browser UI is only useful if the underlying Xbox machine, storage,
timers, CPU execution, and display path are working.

## Build With Containers

All local builds should go through the container wrappers so clean rebuilds are
repeatable. The scripts use Docker by default. This environment normally uses
Podman, so either set `XEMU_DOCKER=podman` or use the local Docker-to-Podman
wrapper by prepending `/tmp/xemu-podman-wrapper` to `PATH`.

Build the native Linux target:

```sh
XEMU_DOCKER=podman XEMU_NATIVE_JOBS=4 scripts/docker-build.sh native
```

Build the browser/WASM target:

```sh
XEMU_DOCKER=podman XEMU_WASM_JOBS=4 scripts/docker-build.sh wasm
```

Build both supported targets:

```sh
XEMU_DOCKER=podman XEMU_NATIVE_JOBS=4 XEMU_WASM_JOBS=4 scripts/docker-build.sh all
```

For this sandbox, the equivalent wrapper form is:

```sh
env PATH=/tmp/xemu-podman-wrapper:/usr/local/bin:/usr/bin:/bin \
  XEMU_NATIVE_JOBS=4 \
  XEMU_WASM_JOBS=4 \
  scripts/docker-build.sh all
```

`scripts/docker-build.sh wasm` rebuilds the Emscripten sysroot first, builds
`qemu-system-i386.js`, then runs `scripts/xbox-verify-wasm-profile.sh`.

For destructive proof from a clean tree:

```sh
scripts/docker-verify-clean-build.sh --yes
```

That script refuses to run if tracked files are dirty or untracked non-ignored
files exist, then runs `git clean -fdx` and `scripts/docker-build.sh all`.
Commit or stash useful local files before using it.

The WASM sysroot depends on committed patches in `patches/`. If a clean build
fails after `git clean -fdx`, first check that the patches exist and are tracked:

```sh
git ls-files patches
```

Run the browser boot page:

```sh
python3 scripts/serve-xbox-browser-boot.py
```

Then open:

```text
http://127.0.0.1:8765/browser/xbox-boot/
```

The server auto-exposes local Xbox assets through `/__xemu_assets__/`. Default
paths are configured in `scripts/serve-xbox-browser-boot.py`, and can be
overridden with `XEMU_BROWSER_MCPX`, `XEMU_BROWSER_FLASH`,
`XEMU_BROWSER_EEPROM`, and `XEMU_BROWSER_HDD`.

## Where To Focus First

Most useful browser/Xbox work will be in these areas:

- `hw/xbox/`: Xbox machine setup, chipset devices, MCPX, SMBus, EEPROM,
  gamepad, NV2A GPU, and related device behavior.
- `hw/xbox/xbox.c`: top-level Xbox machine construction and boot-time machine
  wiring.
- `hw/xbox/xbox_pci.c`: Xbox PCI/LPC/SMBus bridge behavior.
- `hw/xbox/nv2a/`: Xbox GPU device, PFIFO/PGRAPH/PCRTC/timer/display behavior.
- `hw/xbox/mcpx/`: MCPX audio/network/ACI pieces.
- `xemu-xbe.c`: XBE/dashboard detection and boot tracing logic.
- `ui/xemu-headless.c`: headless/browser boot runtime entry and timeout path.
- `browser/xbox-boot/`: browser host page, worker, block-device bridge, and
  asset loading.
- `scripts/serve-xbox-browser-boot.py`: local browser server and asset
  preloading.
- `scripts/docker-build*.sh`: containerized native and WASM build flow.
- `scripts/xbox-verify-wasm-profile.sh`: guardrail for the expected browser
  build profile.

Start with those paths before broad searches through the whole QEMU tree.

## Xbox-Specific vs QEMU-Generic

This repo is mostly QEMU infrastructure plus xemu's Xbox-specific layer. A rough
tracked-source estimate:

- Total repo: about 11,373 tracked files and about 3.76M counted lines.
- Obvious xemu/Xbox/browser-specific code: about 210 files and 66k lines.
- That means the Xbox-authored layer is only around 2 percent of the tree by
  files/lines.

That does not mean the other 98 percent is dead. The Xbox-specific code depends
on generic QEMU systems for CPU execution, memory, devices, block storage,
timers, the main loop, object modeling, tracing, and build machinery.

Common QEMU-generic areas that still matter:

- `target/i386/`: x86 CPU model and translated execution.
- `tcg/` and `accel/tcg/`: CPU translation/execution engine.
- `system/`, `hw/core/`, `qom/`, `qapi/`, `util/`: core emulator runtime.
- `block/` and `hw/ide/`: HDD/DVD image and IDE paths used by Xbox boot.
- `hw/usb/` and `hw/input/`: controller/input plumbing.
- `ui/`: display, headless, and host integration layers.

Large parts of the repo are not central to Xbox browser boot, for example many
non-i386 targets, other machine boards, broad QEMU tests, Linux/BSD user-mode
emulation, CI, docs, and release tooling. Avoid treating those as the first
place to investigate unless the build, trace, or call path points there.

## Browser Build Profile

The browser profile intentionally builds a smaller headless Xbox emulator:

- target: `i386-softmmu`
- browser option: `--enable-xemu-browser-boot`
- CPU execution: TCG interpreter
- UI entry: `ui/xemu-headless.c`
- renderer: NV2A null renderer for browser/headless work
- required device path includes IDE core

The browser profile intentionally excludes desktop UI and desktop renderers such
as SDL, xemu desktop UI, imgui, OpenGL NV2A, Vulkan NV2A, and GLSL renderer
paths. See `scripts/xbox-verify-wasm-profile.sh` for the exact required and
forbidden compile patterns.

## Debugging Notes

Normal browser runs should stay quiet. Boot tracing is opt-in:

```sh
XEMU_BOOT_TRACE=1 python3 scripts/serve-xbox-browser-boot.py
```

When debugging browser boot, prefer focused evidence from the Xbox/browser paths
above before adding broad logging. Keep logs small, timestamped when timing
matters, and tied to one question the next run can answer.
