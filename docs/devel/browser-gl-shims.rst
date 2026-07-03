Browser GL shims
================

This document describes the temporary browser graphics shims on the
``browser-v2-disp`` branch as of July 3, 2026. It is meant to be a map for
future cleanup work. The current branch can run the emulator in the browser and
can move pixels into the browser canvas, but it does not yet prove that the
browser is showing the same final frame that normal desktop xemu would show.

The important distinction is frame source. A ``surface`` frame is copied from
QEMU's display surface. A ``vram`` frame is copied directly from emulated Xbox
video memory. Both are useful debugging probes, but both can show intermediate
or stale data. A trusted browser display should come from ``gl-readback`` or an
equivalent path after the NV2A renderer has rendered the final display frame.

Terms
-----

NV2A is the original Xbox GPU that xemu emulates. The desktop renderer uses
OpenGL to emulate it. The browser build uses WebGL2 through Emscripten, which is
similar to OpenGL ES but stricter than desktop OpenGL.

A surface is a GPU image or render target. The guest can draw into it, copy from
it, or use it as a texture. Normal xemu keeps many of these in a surface cache.

A framebuffer is the set of attachments that OpenGL or WebGL renders into. A
framebuffer is complete only if all attached color and depth images are legal
and compatible. Desktop OpenGL accepts some combinations that WebGL rejects.

``SurfaceBinding`` is the renderer-side record for one cached surface. It
stores the guest surface address, size, pitch, Xbox format, WebGL/OpenGL
texture id, and whether the surface is color or depth. When this document says
"surface binding," it means one of these cached GPU surfaces.

Current status
--------------

The browser boot page can start the wasm build, load the Xbox boot assets, and
run interactive mode. The worker stays alive long enough to reach NV2A worker
threads and display updates.

The display bridge can post frames to the browser canvas. The page logs the
source of each frame as ``surface``, ``vram``, ``gl-texture``, or
``gl-readback``. The page also preserves the last nonblack frame so later black
fallback frames do not immediately erase visible evidence.

The remaining graphics blocker is that the browser usually logs
``Browser display: GL framebuffer unavailable``. That means the display bridge
asked the NV2A renderer for the final rendered framebuffer, but the renderer did
not return one. When this happens, the browser falls back to ``surface`` or
``vram`` probes. These probes are not enough to claim useful rendering.

Display bridge shims
--------------------

``ui/xemu-browser-display.c`` registers a QEMU display listener for browser
builds. It converts QEMU display surfaces into RGBA and posts them to
JavaScript through ``xemu_browser_display_post_frame``. This is the source of
``source=surface`` frames.

The same file asks the NV2A renderer for a framebuffer texture through
``nv2a_get_framebuffer_surface``. In browser builds this is mostly a trigger:
the NV2A display thread owns the WebGL context, so the real readback must happen
while that context is current. The log line
``Browser display: requested GL framebuffer`` means this path returned a
texture id. The log line ``Browser display: GL framebuffer unavailable`` means
it did not.

``hw/xbox/nv2a/nv2a.c`` adds a direct VRAM reader for browser diagnostics. It
uses the VGA resolution, pitch, start address, and color depth to copy raw
emulated video memory into RGBA. This is the source of ``source=vram`` frames.
The logs beginning ``Browser display: vram copy skipped`` explain why that
fallback could not decode a frame.

The browser page and worker in ``browser/xbox-boot`` tag each posted frame with
its source and whether it has nonblack pixels. Black frames are throttled in the
worker. The page keeps the last nonblack frame instead of repainting it with
black fallback frames.

WebGL object table shims
-----------------------

Emscripten tracks WebGL objects in JavaScript tables such as ``GL.textures``,
``GL.framebuffers``, ``GL.shaders``, and ``GL.programs``. Some xemu paths create
or bind objects in ways that exposed missing or stale table entries in the
browser build.

``hw/xbox/nv2a/pgraph/thirdparty/epoxy-emscripten/epoxy/gl.h`` redirects a set
of GL calls to browser wrappers when ``XEMU_BROWSER_GL_EXPERIMENT`` is enabled.
The wrappers live in ``hw/xbox/nv2a/pgraph/thirdparty/gloffscreen/sdl.c``.

The current wrapper set covers object creation for buffers, framebuffers,
queries, renderbuffers, textures, vertex arrays, programs, and shaders. It also
covers selected bind, buffer upload, texture upload, ``glGetIntegerv``,
``glGetString``, and ``glGetError`` behavior.

The program and shader wrappers exist because WebGL reported
``shaderSource: Argument 1 is not an object``. That error meant C code had a
numeric shader id, but Emscripten's ``GL.shaders`` table did not contain a real
``WebGLShader`` object for that id. The wrapper creates the WebGL object from
the active context and stores it in the expected table.

These wrappers are temporary compatibility code. The eventual fix should be a
smaller, verified WebGL backend layer that keeps Emscripten's GL object tables
and xemu's GL abstraction in sync without ad hoc patches.

Format and framebuffer shims
----------------------------

``hw/xbox/nv2a/pgraph/gl/constants.h`` maps several Xbox color surface formats
to WebGL-renderable RGBA8 storage in browser builds. It also maps browser
``GL_CLAMP_TO_BORDER`` use to ``GL_CLAMP_TO_EDGE``, because WebGL does not
support border clamp.

``hw/xbox/nv2a/pgraph/gl/surface.c`` converts browser color surfaces between
native Xbox layouts and RGBA storage. This lets the emulated guest keep seeing
the expected Xbox pixel layout while WebGL receives a format it can render to.
This is not yet a complete or proven format strategy.

The same file detaches mismatched depth or zeta attachments in browser builds.
A zeta attachment is the depth/stencil render target associated with a color
target. WebGL rejects framebuffers where color and zeta attachments have
incompatible sizes. Normal desktop OpenGL paths are left unchanged.

The browser path also skips some incomplete framebuffers instead of asserting.
The relevant logs are ``Browser GL: skipping incomplete surface framebuffer``
and ``Browser GL: skipping incomplete surface-to-texture framebuffer``. These
logs mean WebGL rejected a framebuffer setup that desktop xemu would normally
expect to work or that the current browser format translation did not make
valid yet.

Skipping is a guardrail, not correctness. The future fix is to make each of
those framebuffer setups valid in WebGL or route that operation through a
correct conversion shader or CPU fallback.

Display-renderer shims
----------------------

``hw/xbox/nv2a/pgraph/gl/display.c`` uses GLSL ES shader sources in browser
builds. It also has a browser readback helper that calls ``glReadPixels`` after
``render_display`` and posts ``source=gl-readback``. This is the path we want to
trust eventually.

The same file logs display synchronization decisions. ``Browser GL: sync
skipped reason=no-display-surface`` means the renderer could not find a cached
surface for the display address. ``Browser GL: sync display surface`` means it
did find one. ``Browser GL: readback frame`` means pixels were read after the GL
display render step.

There is a browser-only fallback lookup at ``pcrtc.start`` in addition to
``pcrtc.start + line_offset``. ``pcrtc.start`` is the display start address in
emulated video memory. ``line_offset`` is the display pitch. This fallback is
diagnostic; the correct lookup rule should be proven against normal xemu before
it is considered final.

Draw and shader shims
---------------------

``hw/xbox/nv2a/pgraph/gl/draw.c`` skips browser draws when neither a color nor
zeta surface binding is complete. The log is ``Browser GL: skipping draw with
no complete surface binding``. This keeps the browser worker alive after WebGL
rejects a target, but it also means rendering work was dropped.

``hw/xbox/nv2a/pgraph/gl/shaders.c`` drains stale WebGL errors before shader
binary cache load/save paths. Desktop OpenGL supports program binary caching in
ways that are not reliable in this browser path. In the browser build, a stale
GL error now causes shader binary reuse to fail and fall back instead of
aborting.

This is also temporary. The correct browser renderer should either disable
program binary caching cleanly for WebGL or implement a WebGL-safe shader cache
strategy.

Runtime and build shims
-----------------------

``system/runstate.c``, ``include/system/system.h``, and ``ui/xemu-headless.c``
add a nonblocking main loop path for the browser run. This lets interactive
mode yield back to the browser event loop instead of returning immediately or
blocking the page permanently.

``hw/xbox/nv2a/pgraph/pgraph.c`` uses guarded BQL locking in a few browser-hit
paths. BQL means "big QEMU lock"; it protects shared emulator state. The change
avoids double-locking in the browser runtime.

``configs/meson/emscripten.txt`` lowers wasm memory from 2 GB to 1536 MB. This
keeps Firefox happier with the current wasm build.
``scripts/docker-build-wasm-sysroot.sh`` rebuilds libffi with BigInt support,
which is required by the current browser runtime.

Harness shims
-------------

``scripts/xbox-browser-runtime-firefox-bidi.mjs`` can now wait for display
evidence. It supports checks for any display frame and for a visible nonblack
canvas sample. This is useful for smoke testing the bridge, but it is not a
correctness test for Xbox rendering.

For visual display progress, the harness should capture frame strips for human
review rather than producing automated image scores. The browser and native
paths can run at different speeds, and the current work is still exploratory.
See ``docs/devel/browser-display-visual-review.rst`` for the capture workflow.

How to read the logs
--------------------

``BROWSER_WORKER_DISPLAY ... source=surface`` means the browser worker received
a QEMU display surface frame.

``BROWSER_WORKER_DISPLAY ... source=vram`` means the worker received a direct
VRAM decode frame.

``BROWSER_WORKER_DISPLAY ... source=gl-readback`` means the worker received a
frame after the browser GL display render/readback path. This is the important
milestone.

``BROWSER_DISPLAY_FRAME result=pass ... nonblack=yes`` means the page drew
nonblack pixels. It does not prove those pixels match normal xemu.

``Browser display: GL framebuffer unavailable`` means the display bridge could
not get the final NV2A framebuffer from the renderer.

``Browser GL: skipping ... framebuffer`` means WebGL rejected an attachment
setup and the browser shim skipped the operation to keep running.

What should be replaced later
-----------------------------

The framebuffer skip paths should be replaced with WebGL-complete render target
creation, format conversion, or readback code.

The direct ``surface`` and ``vram`` display fallbacks should remain debugging
tools, not success criteria.

The WebGL object wrappers should be reduced to a small, intentional browser GL
backend once we understand which Emscripten table mismatches are real.

The shader binary cache fallback should become an explicit WebGL policy.

The final success signal should be stable ``source=gl-readback`` frames that
match normal desktop xemu output at the same rendering boundary.
