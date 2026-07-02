# Deterministic Warmup Loop Check

1. Are we looping? If yes, which repeated action or assumption proves it?

Yes. The loop is scalar warmup tuning. History 64 proved the effective two-tick
variant can move `pre_service_browser_first_watch_read_ticks` to 2 but loses
`0x80030e84->0x80030f31`. History 66 proved the one-event split cap loses the
watched read and falls to `0x8001b02f->0x8001b030`. The repeated assumption is
that a warmup count can be tuned into both tick progress and preserved CPU flow.

2. What is the narrowest next fact that changes the current boundary?

Why `browser_post_service_top_edge` changes from the useful baseline
`0x80030e84->0x80030f31` to either `0x80030e4c->0x80014f32` or
`0x8001b02f->0x8001b030`. Specifically: what CPU/IRQ/PIC/timer state first
differs at the edge decision, not how many warmup ticks were injected.

3. Which hypothesis should be killed, kept, or revised?

Kill: raw deterministic warmup count as the main control knob.

Keep: deterministic timer delivery as diagnostic evidence, because it can move
the watched word without weakening strict B6.

Revise: deterministic mode must be phase/state-gated around CPU-flow
invariants, not capped by a simple event count.

4. Is a next step justified by the loop guard? Name the exact field it can
change or explain.

Yes, only if it targets `browser_post_service_top_edge`. That field can explain
both regressions: missing first watched read in history 66 and missing browser
post edge in history 64.

5. What is one better experiment or code slice, if any, and what field would it
change?

Add a narrow edge-decision trace around the first post-stream-idle CPU edges,
logging PC transition, `cpu_interrupt_request`, pending interrupt, PIC
ack/reset state, watched `0x0003a890` ticks, and timer source before/after each
deterministic dispatch. Compare old ready-edge baseline, history 64, and
history 66. The field it changes or explains is `browser_post_service_top_edge`.

revise
