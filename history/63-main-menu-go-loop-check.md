# Main Menu Go Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

No, not yet. `history/62` explained a new boundary fact: browser runtime reaches `xemu_xbe_boot_trace_mark_executed()` and is rejected by strict section/physical-match logic. The loop to avoid now is repeating call-chain, pump-placement, B3/B4/B5, or native-reference checks that only reconfirm `missing-xbe-executed-marker` and `pre_service_browser_first_watch_read_ticks=0`.

2. What is the narrowest next fact that changes the current boundary?

Whether an opt-in deterministic browser path can produce an ordered pre-first-read timeline where due timer, PFIFO, interrupt, and CPU-resume work occurs before the browser reads physical `0x0003a890`. The boundary changes if `browser_first_watch_read_ticks` moves above 0, or if the timeline names the exact pre-read event that prevents it before `0x80014f32->0x80030e84`.

3. Which hypothesis should be killed, kept, or revised?

Kill: browser failure is due to not reaching `mark_executed()` or missing call-chain flag delivery. Kill: more broad host-pump count, pump-placement, B3/B4/B5, or native-reference proof is likely to satisfy B6. Keep: the strict dashboard detector is valid and must not be weakened. Keep: the active causal boundary is browser tick accumulation/order before the first watched read. Revise: deterministic mode must be a real opt-in boot-ordering control and compact timeline gate, not another ungated diagnostic wrapper around the same ready-edge pump.

4. Is the proposed next code slice justified by the loop guard? Name the exact field it can change or explain.

Yes, if it stays scoped to opt-in M1 infrastructure and is followed by one focused run. The exact field is `browser_first_watch_read_ticks`; secondarily it can explain why `browser_dashboard_xbe_executed` remains false, but it must not synthesize or relax strict `dashboard=xbe-executed`.

5. What is one better experiment or code slice, if any, and what field would it change?

The better version of the slice is to make `XEMU_BROWSER_BOOT_DETERMINISTIC=1` emit one sequence-numbered deterministic timeline for due-timer dispatch, PFIFO scheduler/kick, hard IRQ set/reset, PIC ack, CPU resume, first `0x0003a890` read/write, and `mark_executed` candidates, capped around the first watched read. If one behavior change is included, drain due QEMU timers once before CPU resume at the PFIFO ready edge under the same flag. Field: `browser_first_watch_read_ticks`; if it does not move, the same timeline should identify the last missing pre-read event.

continue
