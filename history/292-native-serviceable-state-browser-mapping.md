# 292 - Native Serviceable State Browser Mapping

## Purpose

Map `native_pre_stream_serviceable_state_browser_mapping` from existing stable
native/browser logs only.

## Commands

```sh
awk 'NR>=1036 && NR<=1048 {printf "%d:%s\n", NR, $0}' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

awk 'NR>=2296 && NR<=2306 {printf "%d:%s\n", NR, $0}' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

awk 'NR>=3748 && NR<=3758 {printf "%d:%s\n", NR, $0}' \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log

awk 'NR>=2486 && NR<=2516 {printf "%d:%s\n", NR, $0}' \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log

rg -n "cpu=hard-irq-service.*intno=0x30|cpu=iret|main-loop=timers|pit=irq-timer|pic=irq-ack.*intno=0x30|dashboard=kernel-loop-probe" \
  build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log \
  build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log
```

## Inputs / Artifacts

- Native baseline:
  `build-real-b3-matrix/native-headless-graphic-update-v2/boot-smoke.log`
- Stable browser baseline:
  `build-real-b3-matrix/browser-memory-watch-write-0x3a890-ready-edge-host4-v1-combined.log`

## Loop-Guard Field

- `native_pre_stream_serviceable_state_browser_mapping`

## Findings

Native serviceable state:

- Native has pre-stream vector `0x30` service before PFIFO stream-idle.
- First observed native service frame:
  - line 1037: edge `0x800141b0->0x80018d30`, IF enabled, IRQ pending,
    wait source/op `pcrtc/intr-clear`, `dma_get=dma_put=0x03880000`.
  - line 1040: PIC ack `intno=0x30`.
  - line 1041: `cpu=hard-irq-service phase=before intno=0x30 eip=0x80018d30`.
  - line 1042: service after-state at `eip=0x80030e4c`.
- Later native pre-stream service repeats at line 2301 with
  `eip=0x80030cca`, IF enabled, wait source/op `pcrtc/intr-clear`, before the
  shared stream-idle boundary.
- At native stream-idle:
  - line 3750 has `eip=0x80014f5f`, `dma_get=dma_put=0x03881318`,
    `pmc_pending=0x01000000`, `pcrtc_pending=0x00000001`.
  - line 3755 reads the watched word at `0x0014c080` / 136 ticks.

Browser comparison:

- Browser has no vector `0x30` service before stream-idle in the stable log.
- Browser reaches the pre-transition point at line 2488:
  - edge `0x8001b02f->0x8001b030`;
  - IF enabled, no pending IRQ;
  - wait source/op `pfifo-window/puller-method-done`;
  - `dma_to_put=12`;
  - `pcrtc_pending=0x00000000`, `pmc_pending=0x00000000`.
- Browser stream-idle happens immediately after at lines 2489-2493, with
  `dma_get=dma_put=0x03881318`.
- Browser first vector `0x30` service is after stream-idle:
  - line 2499 PIC ack `intno=0x30`;
  - line 2500 service before-state at `eip=0x8001b030`;
  - line 2501 service after-state at `eip=0x80030e4c`.
- Browser first watched read at line 2511 still reads `0x00000000` / 0 ticks.

## Decision

Classify the mapping as:

```text
native_pre_stream_serviceable_state_browser_mapping=no-equivalent-browser-state-before-stream-idle
```

The native state is not just "timer expired before PFIFO empty"; it is repeated
pre-stream vector service while the NV2A wait state is `pcrtc/intr-clear`, with
PIT/PIC progress and nonzero display/PCRTC state accumulating before the shared
stream-idle boundary. The stable browser never reaches an equivalent
pre-stream serviceable state. Its timer/vector work starts after stream-idle
from the `0x8001b030` path.

## Next Step

Run the required bounded loop check. The likely next action is to update
`goal.md` with this boundary and require a revised design before any runtime or
new instrumentation.
