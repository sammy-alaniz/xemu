# 198. First NV_USER DMA_PUT Ordering Context

## Purpose

Explain the new field `first_nv_user_dma_put_ordering_context` using only the existing source-tag browser artifact. This was a bounded static extraction to determine whether the log already shows why the first `nv-user-dma-put` PFIFO kick occurs after the timer-opportunity window.

## Commands

```sh
rg -n -m 16 'headless=timer-opportunity' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
rg -n -m 24 'pfifo=scheduler' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
rg -n -m 24 'kick_source=nv-user-dma-put|nv-user-dma-put' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
awk 'NR>=1158 && NR<=1172 {printf "%d:%s\n", NR, $0}' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
awk 'NR>=1378 && NR<=1392 {printf "%d:%s\n", NR, $0}' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
awk 'NR>=1256 && NR<1385 && /BOOT_MARK b6/ {printf "%d:%s\n", NR, $0}' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
awk 'NR>=1256 && NR<1385 && /cpu_known|eip=0x|pfifo=scheduler|nv-user-dma-put|headless=timer-opportunity/ {printf "%d:%s\n", NR, $0}' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
rg -n -m 12 'pfifo_boot_trace_scheduler_state|kick_source|cpu_known|eip=' hw/xbox/nv2a/pfifo.c hw/xbox/nv2a/user.c
awk 'function f(name, i, a) { for (i = 1; i <= NF; i++) { if ($i ~ "^" name "=") { split($i, a, "="); return a[2]; } } return "-" } NR==1255 || NR==1331 || NR==1333 || NR==1336 || NR==1338 || NR==1358 || NR==1375 || NR==1385 { printf "%d dashboard=%s headless=%s pfifo=%s seq=%s obs=%s eip=%s guest_pc=%s start_pc=%s next_pc=%s wait_get=%s wait_put=%s nv2a_get=%s nv2a_put=%s dma_get=%s dma_put=%s kick_source=%s mem_watch=%s read_lba=%s contiguous_bytes=%s\n", NR, f("dashboard"), f("headless"), f("pfifo"), f("seq"), f("observed_seq"), f("eip"), f("guest_pc"), f("start_pc"), f("next_pc"), f("wait_dma_get"), f("wait_dma_put"), f("nv2a_dma_get"), f("nv2a_dma_put"), f("dma_get"), f("dma_put"), f("kick_source"), f("memory_watch_value"), f("read_lba"), f("contiguous_bytes") }' build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log
```

## Inputs and Artifacts

- `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-pfifo-kick-source-v1/browser-runtime.log`
- `hw/xbox/nv2a/user.c`
- `hw/xbox/nv2a/pfifo.c`

## Loop-Guard Fields

- `first_nv_user_dma_put_ordering_context`
- `first_nv_user_dma_put_writer_marker_coverage`

## Findings

The last timer opportunity in this artifact is line 1255:

```text
line=1255 headless=timer-opportunity seq=8 eip=0x8001b0b5 wait_dma_get=0x03880000 wait_dma_put=0x03880000 memory_watch_value=0x00000000
```

It is still blocked by the same condition: no PFIFO window/source has appeared yet, and PFIFO has no DMA work because `wait_dma_get == wait_dma_put`.

After that, existing CPU-flow markers show the browser CPU repeatedly in the kernel-loop probe at `0x80031ffa`, still with no PFIFO work:

```text
line=1331 dashboard=kernel-loop-probe eip=0x80031ffa nv2a_dma_get=0x03880000 nv2a_dma_put=0x03880000
line=1333 dashboard=kernel-loop-probe eip=0x80031ffa nv2a_dma_get=0x03880000 nv2a_dma_put=0x03880000
line=1336 dashboard=kernel-loop-probe eip=0x80031ffa nv2a_dma_get=0x03880000 nv2a_dma_put=0x03880000
line=1338 dashboard=kernel-loop-probe eip=0x80031ffa nv2a_dma_get=0x03880000 nv2a_dma_put=0x03880000
```

The log then shows more dashboard XBE read progress:

```text
line=1358 dashboard=xbe-read-progress guest_pc=0x80024307 read_lba=4609512 contiguous_bytes=167936
line=1375 dashboard=xbe-read-progress guest_pc=0x80024307 read_lba=4609520 contiguous_bytes=172032
```

The first PFIFO scheduler event occurs at line 1385, 130 log lines after the last timer opportunity:

```text
line=1385 pfifo=scheduler op=kick kick_source=nv-user-dma-put dma_get=0x03880000 dma_put=0x03881300 dma_to_put=4864
```

This changes the ordering interpretation. The first post-opportunity PFIFO kick occurs because the guest finally publishes PFIFO DMA work by writing `NV_USER_DMA_PUT`, moving `DMA_PUT` from `0x03880000` to `0x03881300`. Before that point, the timer opportunities and kernel-loop probes all show `DMA_GET == DMA_PUT`, so there is no PFIFO command window to consume.

The existing scheduler marker does not include exact CPU writer context for the `NV_USER_DMA_PUT` write. Source inspection confirms `pfifo_boot_trace_scheduler_state()` logs PFIFO state and `kick_source`, but not guest EIP/register context. Existing nearby CPU markers are therefore enough to show ordering, but not enough to prove the exact guest instruction that wrote DMA_PUT.

## Decision

Do not continue generic PFIFO log mining. The current artifact answers the PFIFO-side ordering: no DMA work exists during the opportunity window, then the guest later publishes DMA work through `NV_USER_DMA_PUT`.

The remaining gap is marker coverage at the guest MMIO write boundary. The next useful step is either:

- add a targeted diagnostic marker at `NV_USER_DMA_PUT` with guest CPU context, DMA old/new values, and current pre-service tick state; or
- return to the stable pre-service CPU/tick boundary if we do not want more instrumentation.

## Next Step

Run the required loop check with progress-method critique before choosing a marker-coverage code change.
