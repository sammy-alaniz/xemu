# 274 - Deferred DMA PUT Activation Plumbing Static

## Purpose

Check whether the safer deferred DMA PUT observer can be activated in the
browser/WASM runtime before attempting any runtime preservation experiment.

## Commands

```sh
rg -n "NV2A_USER_DMA_PUT|USER_DMA_PUT|nv2a_user_dma_put|dma_put_limit|DMA_PUT_LIMIT|XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT" scripts browser hw/xbox/nv2a
rg -n "xemu-fixtures|boot_trace_context|memory_watch|timer_opportunity|createDataFile|FS\\.writeFile|writeFile|fixture|fixtures" scripts/xbox-browser-runtime-smoke.sh scripts/xbox-browser-runtime-firefox-bidi.mjs browser/xbox-boot/main.js browser/xbox-boot/worker.js
sed -n '470,545p' browser/xbox-boot/main.js
sed -n '220,285p' browser/xbox-boot/worker.js
sed -n '350,372p' browser/xbox-boot/worker.js
sed -n '620,705p' scripts/xbox-browser-runtime-smoke.sh
sed -n '510,590p' scripts/xbox-browser-runtime-firefox-bidi.mjs
rg -n "traceOptions|XEMU_BROWSER_BOOT_|XEMU_BOOT_TRACE_" scripts/xbox-browser-runtime-smoke.sh scripts/xbox-browser-runtime-firefox-bidi.mjs
rg -n "traceOptionSpecs|xemuBrowserBoot|dataset|traceOptions" browser/xbox-boot/main.js browser/xbox-boot/worker.js
```

## Inputs / Artifacts

- `hw/xbox/nv2a/user.c`
- `browser/xbox-boot/main.js`
- `browser/xbox-boot/worker.js`
- `scripts/xbox-browser-runtime-smoke.sh`
- `scripts/xbox-browser-runtime-firefox-bidi.mjs`

## Loop-Guard Field

- `deferred_dma_put_observer_browser_activation_plumbing_status`

## Findings

- The C observer now reads `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` or
  `nv2a_user_dma_put_limit.txt` from `/xemu-fixtures`, `/xemu-smoke`, or
  `/xemu-smoke-out`.
- No browser script currently maps
  `XEMU_BOOT_TRACE_NV2A_USER_DMA_PUT_LIMIT` into `traceOptions`.
- `browser/xbox-boot/main.js` has no `traceOptionSpecs` entry for a DMA PUT
  limit.
- `browser/xbox-boot/worker.js` has no `traceOptionSpecs` entry that writes
  `/xemu-fixtures/nv2a_user_dma_put_limit.txt`.
- Browser runtime summary output does not report a DMA PUT trace option, so a
  runtime would not prove whether the observer activated.

## Decision

Activation plumbing is missing. Do not run a runtime preservation experiment
yet.

## Next Step

Run the required bounded loop check. The next likely field is
`deferred_dma_put_observer_activation_plumbing_build_status`, but only if the
loop check approves a narrow browser plumbing patch plus build/static checks.
