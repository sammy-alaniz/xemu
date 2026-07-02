# Call Chain Browser Runtime Pre-Run Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

No. The earlier loop risk was repeating the assumption that a host environment flag would reach browser/WASM. History 60 changed that condition by plumbing `XEMU_BOOT_TRACE_CALL_CHAIN` through browser `traceOptions` into `/xemu-fixtures/call_chain_trace.txt` and rebuilding `build-wasm-pic`. The proposed run would become looping only if it is used to reconfirm known B4/B5/read/load/entry-ready evidence or the already-known strict B6 failure without inspecting the new `CALL_CHAIN` markers.

2. What is the narrowest next fact that would change the B6 boundary?

The narrowest fact for this slice is whether the browser runtime reaches `xemu_xbe_boot_trace_observe_exec` and `xemu_xbe_boot_trace_mark_executed`, and if so whether `mark_executed` rejects the candidate before emitting `dashboard=xbe-executed`. That explains the current `browser_xbe_executed` absence without weakening the strict B6 contract.

3. Which hypothesis should be killed, kept, or revised?

Kill the hypothesis that call-chain markers are B6 completion evidence or that they move `pre_service_browser_first_watch_read_ticks`. Keep the hypothesis that the browser may reach the execution-marker decision path but reject the candidate before the strict marker. Revise the delivery hypothesis: after history 60, the question is no longer host-env forwarding but browser-runtime marker reachability and rejection point.

4. Is the proposed next run justified by the loop guard? Name the exact field it can change or explain.

Yes, with the stated scope. The exact loop-guard field it can explain is `browser_xbe_executed`, through the diagnostic subfact `browser_call_chain_reaches_mark_executed_attempt`. It does not by itself change the primary tick metric and must not be promoted as B6 evidence.

5. What is one better experiment, if any, and what single loop-guard field would it change?

There is no better experiment for the narrow browser call-chain plumbing question. If prioritizing the primary tick boundary instead, the better experiment remains the source-tagged PFIFO scheduler/kick-source browser run; the single loop-guard field would be `first_kick_after_last_opportunity_source`.

Decision: continue
