# 338 - Guarded Pre-Interrupt Scheduler Build

## Purpose

Apply and build-validate the surgical patch approved by
`history/337-browser-pre-stream-vector-blocker-loop-check.md`.

The code-side field for this verification is:

```text
browser_pre_stream_vector_blocker_build_safe
```

## Commands

```sh
git diff --check -- xemu-xbe.c \
  history/336-browser-pre-stream-vector-blocker-static.md \
  history/337-browser-pre-stream-vector-blocker-loop-check.md
```

```sh
sed -n '2768,2782p' xemu-xbe.c
```

```sh
PATH=/tmp/xemu-podman-wrapper:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin \
XEMU_WASM_SKIP_IMAGE_BUILD=1 \
XEMU_WASM_BUILD_DIR=build-wasm-pic \
XEMU_WASM_JOBS=4 \
scripts/docker-build-xemu-wasm.sh
```

## Inputs / Artifacts

- Patched file: `xemu-xbe.c`
- Build output: `build-wasm-pic/qemu-system-i386.js`
- Build mode: existing Podman WASM image, image rebuild skipped.

## Loop-Guard Field

```text
browser_pre_stream_vector_blocker_build_safe=pass
```

## Findings

Patch applied:

```c
bool xemu_xbe_boot_trace_tcg_timer_pump_before_interrupt(void)
{
    /*
     * Keep the old broad before-interrupt path quarantined. The only allowed
     * owner here is the opt-in pre-first-read scheduler after its site-ready
     * guard has proved the dashboard image is loaded, the CPU is at a bounded
     * serviceable point, and an expired virtual timer is available.
     */
    return xemu_xbe_tcg_timer_pump_pre_first_read_scheduler_ready();
}
```

Validation results:

- `git diff --check` passed for the touched source/history files.
- Podman WASM build passed.
- Build recompiled `xemu-xbe.c.o`.
- Build linked `qemu-system-i386.js`.

No browser runtime was run in this step, per the prior loop-check process
adjustment.

## Decision

Continue. The guarded pre-first-read scheduler owner is build-safe in the
browser/WASM target. The old broad before-interrupt path remains quarantined by
the existing scheduler site-ready guard rather than being reopened globally.

## Next Step

Run the required bounded sub-agent loop check with Progress-Method Critique
before any runtime. The proposed next runtime field is whether the browser now
emits a `scheduler=pre-first-read` timer pump before the first watched read, and
whether `browser_first_watch_read_ticks` moves above zero without regressing
B4/B5/read/load/entry-ready/section-map evidence.

## Progress-Method Critique Included

No. This entry records the code patch and build result. The required follow-up
loop check must include the critique.
