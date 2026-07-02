# Call Chain Browser Runtime Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

Not yet, but the proposed run would loop if it only sets `XEMU_BOOT_TRACE_CALL_CHAIN=1` in the host shell. Histories 56-58 already proved that env delivery, not the call-chain instrumentation itself, was the failure mode in the native wrapper path. The browser runtime has the same class of risk: current browser diagnostics are forwarded through `xemuBrowserBootTraceOptions` and `/xemu-fixtures/*.txt`, while the call-chain code currently checks only `getenv("XEMU_BOOT_TRACE_CALL_CHAIN")`. A browser run that does not first prove that flag reaches the WASM process would repeat the env-forwarding assumption.

2. What is the narrowest next fact that would change the B6 boundary?

For B6 itself, the narrowest next fact is still browser-side causal ordering before dashboard execution, not native call-chain presence. Given history 50/51 resolved the PFIFO kick source as `nv-user-dma-put`, the next B6-relevant fact is whether an earlier guest `NV_USER_DMA_PUT` write exists before the expired timer-opportunity window, and where its guest PC/edge lands relative to the first `0x0003a890` watched read. For the proposed call-chain slice, the narrow fact is only `browser_call_chain_markers_present`, specifically whether browser runtime reaches `xemu_xbe_boot_trace_observe_exec` and `xemu_xbe_boot_trace_mark_executed`.

3. Which hypothesis should be killed, kept, or revised?

Kill the hypothesis that call-chain markers prove B6, move `pre_service_browser_first_watch_read_ticks`, or can be promoted as dashboard-loaded evidence. Keep the hypothesis that browser call-chain markers can explain whether the browser runtime reaches the execution-marker decision path. Revise the delivery hypothesis: native direct Podman env success does not imply browser/WASM env success; browser runtime needs explicit call-chain option forwarding or another verified delivery path before the run is meaningful.

4. Is the proposed next run justified by the loop guard? Name the exact field it can change or explain.

Revise before running. It is justified only if `XEMU_BOOT_TRACE_CALL_CHAIN=1` is actually delivered into the browser/WASM runtime and the run preserves the current browser diagnostic knobs. The exact field it can change or explain is `browser_call_chain_markers_present`, with the sharper subfield `browser_call_chain_reaches_mark_executed_attempt`. That can explain the `browser_xbe_executed` absence, but it does not change the primary tick metric by itself.

5. What is one better experiment, if any, and what single loop-guard field would it change?

The better B6 experiment is a focused browser-runtime DMA PUT provenance/order check: identify the first guest `NV_USER_DMA_PUT` write line, guest PC/edge, value, and ordering relative to the last timer opportunity and first `0x0003a890` watched read. The single loop-guard field it would change or explain is `kick_sources_before_first_opportunity`, now refined to whether the guest DMA PUT source is absent before the opportunity window or merely not converted into a PFIFO kick before then.

Decision: revise
