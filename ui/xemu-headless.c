/*
 * Minimal xemu headless entry point for browser boot and smoke builds.
 */

#include "qemu/osdep.h"
#include "qemu/thread.h"
#include "qemu/main-loop.h"
#include "qemu/timer.h"
#include "qemu/rcu.h"
#include "qemu-version.h"
#include "xemu-version.h"
#include "system/runstate.h"
#include "system/runstate-action.h"
#include "system/system.h"
#include "ui/console.h"
#include "ui/xemu-settings.h"

#if defined(XBOX) || defined(CONFIG_XEMU_BROWSER_BOOT)
#include "xemu-xbe.h"
#endif

#include <locale.h>

static QemuThread thread;
static int exit_status;
static bool qemu_exiting;

static int g_argc;
static char **g_argv;
static int64_t headless_boot_timeout_override_ms = -1;
static QemuThread headless_vblank_thread;
static bool headless_vblank_started;
static bool headless_vblank_stopping;

static const int64_t headless_vblank_interval_us = 16667;

static bool xemu_call_chain_trace_enabled(void)
{
    const char *value = getenv("XEMU_BOOT_TRACE_CALL_CHAIN");

    if (value && value[0]) {
        return strcmp(value, "0");
    }

#ifdef CONFIG_XEMU_BROWSER_BOOT
    static bool initialized;
    static bool enabled;
    const char *paths[] = {
        "/xemu-fixtures/call_chain_trace.txt",
        "/xemu-smoke/call_chain_trace.txt",
        "/xemu-smoke-out/call_chain_trace.txt",
        NULL,
    };
    char buffer[32];

    if (initialized) {
        return enabled;
    }
    initialized = true;

    for (int i = 0; paths[i]; i++) {
        FILE *fp = fopen(paths[i], "r");

        if (!fp) {
            continue;
        }

        if (fgets(buffer, sizeof(buffer), fp)) {
            buffer[strcspn(buffer, "\r\n")] = 0;
        } else {
            buffer[0] = 0;
        }
        fclose(fp);

        if (!buffer[0]) {
            continue;
        }

        enabled = g_ascii_strcasecmp(buffer, "0") &&
                  g_ascii_strcasecmp(buffer, "false") &&
                  g_ascii_strcasecmp(buffer, "no") &&
                  g_ascii_strcasecmp(buffer, "off");
        return enabled;
    }
#endif

    return false;
}

static void xemu_call_chain_trace(const char *event, const char *method)
{
    if (xemu_call_chain_trace_enabled()) {
        fprintf(stderr, "CALL_CHAIN %s %s!\n", event, method);
    }
}

static void xemu_call_chain_trace_once(bool *emitted, const char *event,
                                       const char *method)
{
    if (!*emitted && xemu_call_chain_trace_enabled()) {
        *emitted = true;
        fprintf(stderr, "CALL_CHAIN %s %s!\n", event, method);
    }
}

static bool xemu_boot_trace_enabled(void)
{
#ifdef CONFIG_XEMU_BROWSER_BOOT
    return true;
#else
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
#endif
}

static void xemu_boot_trace_mark(const char *message)
{
    if (xemu_boot_trace_enabled()) {
        fprintf(stderr, "BOOT_MARK %s\n", message);
    }
}

static int64_t xemu_headless_boot_timeout_ms(void)
{
    const char *value = getenv("XEMU_HEADLESS_BOOT_MS");
    char *end = NULL;
    int64_t timeout_ms = 30000;

    if (headless_boot_timeout_override_ms >= 0) {
        return headless_boot_timeout_override_ms;
    }

    if (!value || !value[0]) {
        return timeout_ms;
    }

    timeout_ms = g_ascii_strtoll(value, &end, 10);
    if (end == value || timeout_ms < 0) {
        fprintf(stderr,
                "Invalid XEMU_HEADLESS_BOOT_MS='%s'; using 30000 ms\n",
                value);
        return 30000;
    }

    return timeout_ms;
}

static void xemu_headless_main_loop_lock(void)
{
    bql_lock();
}

static void xemu_headless_main_loop_unlock(void)
{
    bql_unlock();
}

static bool xemu_headless_browser_boot_deterministic_enabled(void);

static void xemu_headless_poll_boot_markers(void)
{
#ifdef XBOX
    if (!xemu_boot_trace_enabled()) {
        return;
    }

    xemu_headless_main_loop_lock();
    xemu_xbe_boot_trace_probe();
    xemu_headless_main_loop_unlock();
#endif
}

static bool xemu_headless_browser_timer_pump_ready(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    if (xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready() &&
        !xemu_headless_browser_boot_deterministic_enabled()) {
        return false;
    }
    return xemu_xbe_boot_trace_main_loop_timer_pump_ready();
#else
    return false;
#endif
}

static bool xemu_headless_browser_timer_pump_poll_active(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    return xemu_xbe_boot_trace_entry_ready();
#else
    return false;
#endif
}

static bool xemu_headless_browser_timer_pump_presleep_enabled(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    return xemu_xbe_boot_trace_main_loop_timer_pump_presleep_enabled();
#else
    return false;
#endif
}

static void xemu_headless_trace_browser_timer_pump_gate(bool ready)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;
    static uint64_t ready_seq;
    static uint64_t pump_ready_seq;
    bool entry_ready;
    bool should_log;

    if (!xemu_boot_trace_enabled()) {
        return;
    }

    entry_ready = xemu_xbe_boot_trace_entry_ready();
    should_log = seq < 8 || (entry_ready && ready_seq < 8) ||
                 (ready && pump_ready_seq < 8);
    seq++;
    if (entry_ready) {
        ready_seq++;
    }
    if (ready) {
        pump_ready_seq++;
    }

    if (!should_log) {
        return;
    }

    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-pump-gate"
            " context=browser-runtime"
            " seq=%llu"
            " entry_ready=%s"
            " pump_ready=%s\n",
            (unsigned long long)seq,
            entry_ready ? "yes" : "no",
            ready ? "yes" : "no");
#else
    (void)ready;
#endif
}

static void xemu_headless_trace_browser_timer_pump_bql_busy(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;

    if (!xemu_boot_trace_enabled() || seq >= 16) {
        return;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-pump-bql"
            " context=browser-runtime"
            " seq=%llu"
            " result=skip"
            " reason=bql-busy\n",
            (unsigned long long)seq);
#endif
}

static bool xemu_headless_read_browser_fixture_setting(const char *file_name,
                                                       char *buffer,
                                                       size_t buffer_size)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    const char *dirs[] = {
        "/xemu-fixtures",
        "/xemu-smoke",
        "/xemu-smoke-out",
        NULL,
    };

    for (int i = 0; dirs[i]; i++) {
        char path[PATH_MAX];
        FILE *fp;

        snprintf(path, sizeof(path), "%s/%s", dirs[i], file_name);
        fp = fopen(path, "r");
        if (!fp) {
            continue;
        }

        if (fgets(buffer, buffer_size, fp)) {
            buffer[strcspn(buffer, "\r\n")] = 0;
        } else {
            buffer[0] = 0;
        }
        fclose(fp);

        if (buffer[0]) {
            return true;
        }
    }
#else
    (void)file_name;
    (void)buffer;
    (void)buffer_size;
#endif

    return false;
}

static bool xemu_headless_browser_boot_deterministic_enabled(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool initialized;
    static bool enabled;
    char file_value[64];
    const char *value;

    if (initialized) {
        return enabled;
    }

    initialized = true;
    value = getenv("XEMU_BROWSER_BOOT_DETERMINISTIC");
    if ((!value || !value[0]) &&
        xemu_headless_read_browser_fixture_setting(
            "browser_boot_deterministic.txt", file_value,
            sizeof(file_value))) {
        value = file_value;
    }

    enabled = value && value[0] &&
              g_ascii_strcasecmp(value, "0") &&
              g_ascii_strcasecmp(value, "false") &&
              g_ascii_strcasecmp(value, "no") &&
              g_ascii_strcasecmp(value, "off");
    return enabled;
#else
    return false;
#endif
}

static uint64_t xemu_headless_browser_boot_deterministic_timer_steps(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool initialized;
    static uint64_t steps = 1;
    char file_value[64];
    const char *value;
    const char *source;
    char *end = NULL;
    int64_t parsed;

    if (initialized) {
        return steps;
    }

    initialized = true;
    value = getenv("XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS");
    source = "XEMU_BROWSER_BOOT_DETERMINISTIC_TIMER_STEPS";
    if ((!value || !value[0]) &&
        xemu_headless_read_browser_fixture_setting(
            "browser_boot_deterministic_timer_steps.txt", file_value,
            sizeof(file_value))) {
        value = file_value;
        source = "browser_boot_deterministic_timer_steps.txt";
    }

    if (!value || !value[0]) {
        return steps;
    }

    parsed = g_ascii_strtoll(value, &end, 10);
    if (end == value || *end || parsed < 1) {
        fprintf(stderr,
                "Invalid %s='%s'; using 1 deterministic timer step\n",
                source, value);
        return steps;
    }

    steps = (uint64_t)parsed;
    return steps;
#else
    return 1;
#endif
}

static int64_t xemu_headless_browser_boot_deterministic_warmup_limit(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool initialized;
    static int64_t limit = 1;
    char file_value[64];
    const char *value;
    const char *source;
    char *end = NULL;
    int64_t parsed;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BROWSER_BOOT_DETERMINISTIC_WARMUP_PROGRESS_LIMIT");
    source = "XEMU_BROWSER_BOOT_DETERMINISTIC_WARMUP_PROGRESS_LIMIT";
    if ((!value || !value[0]) &&
        xemu_headless_read_browser_fixture_setting(
            "browser_boot_deterministic_warmup_progress_limit.txt",
            file_value, sizeof(file_value))) {
        value = file_value;
        source = "browser_boot_deterministic_warmup_progress_limit.txt";
    }

    if (!value || !value[0]) {
        return limit;
    }

    parsed = g_ascii_strtoll(value, &end, 10);
    if (end == value || *end || parsed < 0) {
        fprintf(stderr,
                "Invalid %s='%s'; using 1 deterministic warmup event\n",
                source, value);
        return limit;
    }

    limit = parsed;
    return limit;
#else
    return 1;
#endif
}

static int64_t xemu_headless_browser_timer_pump_progress_limit(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool initialized;
    static int64_t limit = -1;
    char file_value[64];
    const char *value;
    const char *source;
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT");
    source = "XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT";

    if ((!value || !value[0]) &&
        xemu_headless_read_browser_fixture_setting(
            "browser_headless_timer_pump_progress_limit.txt", file_value,
            sizeof(file_value))) {
        value = file_value;
        source = "browser_headless_timer_pump_progress_limit.txt";
    }

    if (!value || !value[0]) {
        return limit;
    }

    limit = g_ascii_strtoll(value, &end, 10);
    if (end == value || *end || limit < 0) {
        fprintf(stderr,
                "Invalid %s='%s'; browser headless timer pump progress "
                "limit disabled\n",
                source, value);
        limit = -1;
    }

    return limit;
#else
    return -1;
#endif
}

static void xemu_headless_trace_browser_timer_pump_progress_limit(
    uint64_t progress_events)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;
    int64_t limit = xemu_headless_browser_timer_pump_progress_limit();

    if (!xemu_boot_trace_enabled() || limit < 0 || seq >= 16) {
        return;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-pump-limit"
            " context=browser-runtime"
            " seq=%llu"
            " result=skip"
            " reason=progress-limit"
            " progress_events=%llu"
            " limit=%lld\n",
            (unsigned long long)seq,
            (unsigned long long)progress_events,
            (long long)limit);
#else
    (void)progress_events;
#endif
}

static void xemu_headless_trace_browser_deterministic_timer(
    const char *phase,
    const char *reason,
    bool ready,
    bool deterministic_ready,
    bool progress,
    uint64_t step_index,
    uint64_t progress_events,
    int64_t progress_limit,
    uint64_t warmup_progress_events,
    int64_t warmup_progress_limit,
    int64_t virtual_now,
    int64_t virtual_deadline,
    bool virtual_has_timers,
    bool virtual_expired)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;
    int64_t virtual_deadline_delta = -1;

    if (!xemu_boot_trace_enabled() ||
        !xemu_headless_browser_boot_deterministic_enabled() || seq >= 64) {
        return;
    }

    if (virtual_deadline >= 0) {
        virtual_deadline_delta = virtual_deadline - virtual_now;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 deterministic=timer-pump"
            " context=browser-runtime"
            " seq=%llu"
            " phase=%s"
            " reason=%s"
            " ready=%s"
            " deterministic_ready=%s"
            " entry_ready=%s"
            " progress=%s"
            " step_index=%llu"
            " progress_events=%llu"
            " progress_limit=%lld"
            " warmup_progress_events=%llu"
            " warmup_progress_limit=%lld"
            " virtual_now=%lld"
            " virtual_deadline=%lld"
            " virtual_deadline_delta=%lld"
            " virtual_has_timers=%s"
            " virtual_expired=%s\n",
            (unsigned long long)seq,
            phase,
            reason,
            ready ? "yes" : "no",
            deterministic_ready ? "yes" : "no",
            xemu_headless_browser_timer_pump_poll_active() ? "yes" : "no",
            progress ? "yes" : "no",
            (unsigned long long)step_index,
            (unsigned long long)progress_events,
            (long long)progress_limit,
            (unsigned long long)warmup_progress_events,
            (long long)warmup_progress_limit,
            (long long)virtual_now,
            (long long)virtual_deadline,
            (long long)virtual_deadline_delta,
            virtual_has_timers ? "yes" : "no",
            virtual_expired ? "yes" : "no");
#else
    (void)phase;
    (void)reason;
    (void)ready;
    (void)deterministic_ready;
    (void)progress;
    (void)step_index;
    (void)progress_events;
    (void)progress_limit;
    (void)warmup_progress_events;
    (void)warmup_progress_limit;
    (void)virtual_now;
    (void)virtual_deadline;
    (void)virtual_has_timers;
    (void)virtual_expired;
#endif
}

static void xemu_headless_trace_browser_timer_pump_step(const char *phase,
                                                        bool progress)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;

    if (!xemu_boot_trace_enabled() || seq >= 32) {
        return;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-pump-step"
            " context=browser-runtime"
            " seq=%llu"
            " phase=%s"
            " progress=%s\n",
            (unsigned long long)seq,
            phase,
            progress ? "yes" : "no");
#else
    (void)phase;
    (void)progress;
#endif
}

static void xemu_headless_trace_browser_timer_pump_step_count(
    uint64_t step_limit,
    bool deterministic)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t seq;

    if (!xemu_boot_trace_enabled() || seq >= 8 || step_limit <= 1) {
        return;
    }

    seq++;
    fprintf(stderr,
            "BOOT_MARK b6 headless=timer-pump-step-count"
            " context=browser-runtime"
            " seq=%llu"
            " deterministic=%s"
            " step_limit=%llu\n",
            (unsigned long long)seq,
            deterministic ? "yes" : "no",
            (unsigned long long)step_limit);
#else
    (void)step_limit;
    (void)deterministic;
#endif
}

static void xemu_headless_pump_browser_timers(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t progress_events;
    static uint64_t deterministic_warmup_progress_events;
    int64_t virtual_now_before;
    int64_t virtual_deadline_before;
    int64_t virtual_now_after;
    int64_t virtual_deadline_after;
    bool virtual_has_timers_before;
    bool virtual_expired_before;
    bool virtual_has_timers_after;
    bool virtual_expired_after;
    bool progress;
    bool ready = xemu_headless_browser_timer_pump_ready();
    bool pcrtc_prestream_ready =
        xemu_xbe_boot_trace_main_loop_timer_pump_pcrtc_prestream_ready();
    bool deterministic = xemu_headless_browser_boot_deterministic_enabled();
    bool deterministic_ready;
    bool deterministic_warmup = false;
    uint64_t deterministic_step_limit = 1;
    int64_t progress_limit =
        xemu_headless_browser_timer_pump_progress_limit();
    int64_t warmup_progress_limit =
        xemu_headless_browser_boot_deterministic_warmup_limit();
    const char *source = "browser-headless-host-pump-bounded";
    const char *ready_reason = "gate-ready";

    xemu_headless_trace_browser_timer_pump_gate(ready);
    virtual_now_before = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_before =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_before = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_before = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    xemu_xbe_boot_trace_observe_browser_timer_opportunity(
        "headless-poll", ready, progress_events, progress_limit,
        virtual_now_before, virtual_deadline_before,
        virtual_has_timers_before, virtual_expired_before);

    if (pcrtc_prestream_ready) {
        source = "browser-deterministic-pcrtc-prestream";
        ready_reason = "pcrtc-intr-clear-prestream";
        if (!virtual_has_timers_before || !virtual_expired_before) {
            xemu_headless_trace_browser_deterministic_timer(
                "blocked", "pcrtc-prestream-no-expired-virtual-timer",
                ready, false, false, 0, progress_events, progress_limit,
                deterministic_warmup_progress_events, warmup_progress_limit,
                virtual_now_before, virtual_deadline_before,
                virtual_has_timers_before, virtual_expired_before);
            return;
        }
    }

    deterministic_ready = ready;
    if (deterministic) {
        deterministic_step_limit =
            xemu_headless_browser_boot_deterministic_timer_steps();
        if (!ready &&
            xemu_headless_browser_timer_pump_poll_active() &&
            virtual_has_timers_before && virtual_expired_before &&
            (warmup_progress_limit < 0 ||
             deterministic_warmup_progress_events <
                 (uint64_t)warmup_progress_limit)) {
            deterministic_ready = true;
            deterministic_warmup = true;
            source = "browser-deterministic-pump";
            ready_reason = "deterministic-warmup-expired-entry-ready";
        } else if (!deterministic_ready) {
            if (warmup_progress_limit >= 0 &&
                deterministic_warmup_progress_events >=
                    (uint64_t)warmup_progress_limit) {
                ready_reason = "deterministic-warmup-limit";
            } else {
                ready_reason = "deterministic-blocked";
            }
        }
        xemu_headless_trace_browser_deterministic_timer(
            "opportunity", ready_reason, ready, deterministic_ready, false,
            0, progress_events, progress_limit,
            deterministic_warmup_progress_events, warmup_progress_limit,
            virtual_now_before, virtual_deadline_before,
            virtual_has_timers_before, virtual_expired_before);
    } else {
        deterministic_step_limit =
            xemu_headless_browser_boot_deterministic_timer_steps();
        xemu_headless_trace_browser_timer_pump_step_count(
            deterministic_step_limit, false);
    }

    if (!deterministic_ready) {
        return;
    }

    if (!deterministic_warmup && progress_limit >= 0 &&
        progress_events >= (uint64_t)progress_limit) {
        xemu_headless_trace_browser_timer_pump_progress_limit(progress_events);
        xemu_headless_trace_browser_deterministic_timer(
            "limit", "progress-limit", ready, deterministic_ready, false,
            0, progress_events, progress_limit,
            deterministic_warmup_progress_events, warmup_progress_limit,
            virtual_now_before, virtual_deadline_before,
            virtual_has_timers_before, virtual_expired_before);
        return;
    }

    if (!bql_try_lock()) {
        xemu_headless_trace_browser_timer_pump_bql_busy();
        return;
    }

    for (uint64_t step = 0; step < deterministic_step_limit; step++) {
        if (step > 0) {
            virtual_now_before = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
            virtual_deadline_before = qemu_clock_deadline_ns_all(
                QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
            virtual_has_timers_before =
                qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
            virtual_expired_before = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
        }

        if (deterministic_warmup && !virtual_expired_before) {
            xemu_headless_trace_browser_deterministic_timer(
                "stop", "no-expired-virtual-timer", ready,
                deterministic_ready, false, step, progress_events,
                progress_limit, deterministic_warmup_progress_events,
                warmup_progress_limit, virtual_now_before,
                virtual_deadline_before,
                virtual_has_timers_before, virtual_expired_before);
            break;
        }
        if (!deterministic_warmup && progress_limit >= 0 &&
            progress_events >= (uint64_t)progress_limit) {
            xemu_headless_trace_browser_timer_pump_progress_limit(
                progress_events);
            xemu_headless_trace_browser_deterministic_timer(
                "limit", "progress-limit", ready, deterministic_ready, false,
                step, progress_events, progress_limit,
                deterministic_warmup_progress_events, warmup_progress_limit,
                virtual_now_before, virtual_deadline_before,
                virtual_has_timers_before,
                virtual_expired_before);
            break;
        }

        if (deterministic_warmup && warmup_progress_limit >= 0 &&
            deterministic_warmup_progress_events >=
                (uint64_t)warmup_progress_limit) {
            xemu_headless_trace_browser_deterministic_timer(
                "limit", "warmup-progress-limit", ready,
                deterministic_ready, false, step, progress_events,
                progress_limit, deterministic_warmup_progress_events,
                warmup_progress_limit, virtual_now_before,
                virtual_deadline_before, virtual_has_timers_before,
                virtual_expired_before);
            break;
        }
        xemu_headless_trace_browser_timer_pump_step("before", false);
        xemu_headless_trace_browser_deterministic_timer(
            "before", ready_reason, ready, deterministic_ready, false, step,
            progress_events, progress_limit, deterministic_warmup_progress_events,
            warmup_progress_limit, virtual_now_before,
            virtual_deadline_before, virtual_has_timers_before,
            virtual_expired_before);
        progress = qemu_clock_run_timers_with_attrs_limit(
            QEMU_CLOCK_VIRTUAL, 0, 0, 1);
        if (progress) {
            if (deterministic_warmup) {
                deterministic_warmup_progress_events++;
            } else {
                progress_events++;
            }
        }
        xemu_headless_trace_browser_timer_pump_step("after", progress);
        virtual_now_after = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
        virtual_deadline_after = qemu_clock_deadline_ns_all(
            QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
        virtual_has_timers_after = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
        virtual_expired_after = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
        xemu_headless_trace_browser_deterministic_timer(
            "after", ready_reason, ready, deterministic_ready, progress, step,
            progress_events, progress_limit, deterministic_warmup_progress_events,
            warmup_progress_limit, virtual_now_after,
            virtual_deadline_after, virtual_has_timers_after,
            virtual_expired_after);
        xemu_xbe_boot_trace_observe_main_loop_timers(
            source, 0, 0, virtual_now_before, virtual_deadline_before,
            virtual_has_timers_before, virtual_expired_before, progress,
            virtual_now_after, virtual_deadline_after,
            virtual_has_timers_after, virtual_expired_after);

        if (deterministic_warmup && !progress) {
            break;
        }
    }
    bql_unlock();
#endif
}

static int64_t xemu_headless_poll_interval_us(void)
{
    if (xemu_headless_browser_timer_pump_poll_active() ||
        xemu_headless_browser_timer_pump_ready()) {
        return 2000;
    }

    return 50000;
}

static void *xemu_headless_vblank_main(void *opaque)
{
    (void)opaque;

    while (!qatomic_read(&qemu_exiting) && !headless_vblank_stopping) {
        QemuConsole *con;

        g_usleep(headless_vblank_interval_us);

        if (qatomic_read(&qemu_exiting) || headless_vblank_stopping) {
            break;
        }

        xemu_headless_main_loop_lock();
        con = qemu_console_lookup_default();
        if (con && qemu_console_is_graphic(con)) {
            graphic_hw_update(con);
        }
        xemu_headless_main_loop_unlock();
    }

    return NULL;
}

static void xemu_headless_vblank_start(void)
{
    if (headless_vblank_started) {
        return;
    }

    headless_vblank_stopping = false;
    qemu_thread_create(&headless_vblank_thread, "headless-vblank",
                       xemu_headless_vblank_main, NULL, QEMU_THREAD_JOINABLE);
    headless_vblank_started = true;
}

static void xemu_headless_vblank_stop(void)
{
    if (!headless_vblank_started) {
        return;
    }

    headless_vblank_stopping = true;
    qemu_thread_join(&headless_vblank_thread);
    headless_vblank_started = false;
}

static void *qemu_main_thread(void *opaque)
{
    static bool started_emitted;
    static bool qemu_main_loop_started_emitted;

    xemu_call_chain_trace_once(&started_emitted, "started",
                               "qemu_main_thread");
    xemu_boot_trace_mark("b0 thread=qemu-main started");
    qemu_init(g_argc, g_argv);
    xemu_headless_vblank_start();
    xemu_call_chain_trace_once(&qemu_main_loop_started_emitted, "started",
                               "qemu_main_loop");
    exit_status = qemu_main_loop();
    xemu_call_chain_trace("ended", "qemu_main_loop");
    if (xemu_boot_trace_enabled()) {
        fprintf(stderr, "BOOT_MARK b3 runstate=main-loop-return exit=%d\n",
                exit_status);
    }
    qatomic_set(&qemu_exiting, true);
    bql_unlock();
#ifdef XBOX
    qemu_mutex_unlock_main_loop();
#endif
    xemu_headless_vblank_stop();

    bql_lock();
    qemu_cleanup(exit_status);
    bql_unlock();

    xemu_call_chain_trace("ended", "qemu_main_thread");
    return NULL;
}

static void parse_xemu_args(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        if (argv[i] && strcmp(argv[i], "-config_path") == 0) {
            argv[i] = NULL;
            if (i < argc - 1 && argv[i + 1]) {
                xemu_settings_set_path(argv[i + 1]);
                argv[i + 1] = NULL;
            }
            break;
        }
    }

    for (int i = 1; i < argc; i++) {
        if (argv[i] && strcmp(argv[i], "-headless_boot_ms") == 0) {
            char *end = NULL;

            argv[i] = NULL;
            if (i < argc - 1 && argv[i + 1]) {
                headless_boot_timeout_override_ms =
                    g_ascii_strtoll(argv[i + 1], &end, 10);
                if (end == argv[i + 1] || headless_boot_timeout_override_ms < 0) {
                    fprintf(stderr,
                            "Invalid -headless_boot_ms '%s'; using default\n",
                            argv[i + 1]);
                    headless_boot_timeout_override_ms = -1;
                }
                argv[i + 1] = NULL;
            }
            break;
        }
    }
}

int main(int argc, char **argv)
{
    static bool started_emitted;
    int64_t timeout_ms;
    int64_t start_us;
    const char *reason = "shutdown";

    xemu_call_chain_trace_once(&started_emitted, "started", "main");

    setlocale(LC_NUMERIC, "C");

    fprintf(stderr, "xemu_version: %s\n", xemu_version);
    fprintf(stderr, "xemu_commit: %s\n", xemu_commit);
    fprintf(stderr, "xemu_date: %s\n", xemu_date);

    g_argc = argc;
    g_argv = argv;
    parse_xemu_args(argc, argv);

    if (!xemu_settings_load()) {
        const char *err_msg = xemu_settings_get_error_message();
        fprintf(stderr, "%s", err_msg);
        exit(1);
    }

    g_config.display.renderer = CONFIG_DISPLAY_RENDERER_NULL;
    g_config.general.updates.check = false;
    g_config.general.show_welcome = false;

    qemu_thread_create(&thread, "qemu_main", qemu_main_thread,
                       NULL, QEMU_THREAD_JOINABLE);
    xemu_boot_trace_mark("b0 thread=qemu-main created");

    timeout_ms = xemu_headless_boot_timeout_ms();
    start_us = g_get_monotonic_time();

    while (!qatomic_read(&qemu_exiting)) {
        int64_t elapsed_ms = (g_get_monotonic_time() - start_us) / 1000;

        xemu_headless_poll_boot_markers();
        xemu_headless_pump_browser_timers();

        if (timeout_ms > 0 && elapsed_ms >= timeout_ms) {
            reason = "timeout";
            qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
            break;
        }

        if (xemu_headless_browser_timer_pump_presleep_enabled()) {
            xemu_headless_pump_browser_timers();
        }
        g_usleep(xemu_headless_poll_interval_us());
    }

    qemu_thread_join(&thread);
    fprintf(stderr,
            "BOOT_SMOKE_RESULT reason=%s elapsed_ms=%lld exit=%d\n",
            reason,
            (long long)((g_get_monotonic_time() - start_us) / 1000),
            exit_status);
    xemu_call_chain_trace("ended", "main");
    return exit_status;
}
