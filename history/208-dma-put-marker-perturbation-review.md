# 208. DMA_PUT Marker Perturbation Review

## Purpose

Perform the source-only perturbation review authorized by `history/207-dma-put-marker-perturbation-loop-check.md`. Do not inspect `nv2a=user-dma-put` fields from the regressed runtime artifact.

## Commands

```sh
sed -n '1,245p' hw/xbox/nv2a/user.c
sed -n '245,360p' hw/xbox/nv2a/user.c
git diff -- hw/xbox/nv2a/user.c
git diff --stat
```

## Inputs and Artifacts

- Source file:
  `hw/xbox/nv2a/user.c`
- Diff context:
  current dirty worktree

## Loop-Guard Fields

- `dma_put_marker_perturbation_risk`
- no marker-field extraction from the regressed runtime

## Findings

`dma_put_marker_perturbation_risk=high`.

The marker is behaviorally intended to be passive, but its current implementation is placed at a sensitive point:

```c
d->pfifo.regs[NV_PFIFO_CACHE1_DMA_PUT] = val;
user_boot_trace_dma_put(...);
...
pfifo_kick_with_source(d, kick_source);
```

That means it runs after the guest publishes `DMA_PUT` but before the PFIFO kick is broadcast. This is exactly the guest-publication-to-PFIFO-scheduler boundary under investigation.

The marker also runs while `d->pfifo.lock` is held. Inside that lock it may:

- initialize context by checking environment and fixture files on the first call;
- call multiple XBE boot-trace state helpers;
- capture guest CPU state through `current_cpu` or `qemu_get_cpu(0)`;
- call `cpu_compute_eflags()`;
- emit a long synchronous `fprintf(stderr, ...)`.

The browser default limit is currently nonzero through:

```c
#ifdef CONFIG_XEMU_BROWSER_BOOT
#define XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 64
#else
#define XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT 16
#endif
```

Even though the test runtime set `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT=16`, the source default means future browser runs would emit this marker unless explicitly disabled. That risks perturbing the stable ready-edge host4 baseline.

## Decision

Do not treat the marker runtime as causal. The preservation guard failed, and the marker implementation has a plausible perturbation path: expensive logging under the PFIFO lock before the kick.

The marker branch should be quarantined before any further browser runtime. The lowest-risk quarantine is to make the DMA_PUT marker opt-in disabled by default for both browser and native builds, preserving the source code for possible later use but preventing accidental baseline perturbation.

## Next Step

Run the required loop check. Proposed bounded action after that: change `XEMU_NV2A_USER_DMA_PUT_TRACE_DEFAULT_LIMIT` to `0`, build only, then return to the stable pre-service CPU/tick boundary rather than rerunning this marker branch.
