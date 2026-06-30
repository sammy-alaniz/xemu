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

static int64_t xemu_headless_browser_timer_pump_progress_limit(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static bool initialized;
    static int64_t limit = -1;
    char file_value[64];
    const char *value;
    const char *source;
    const char *dirs[] = {
        "/xemu-fixtures",
        "/xemu-smoke",
        "/xemu-smoke-out",
        NULL,
    };
    char *end = NULL;

    if (initialized) {
        return limit;
    }

    initialized = true;
    value = getenv("XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT");
    source = "XEMU_BROWSER_BOOT_HEADLESS_TIMER_PUMP_PROGRESS_LIMIT";

    if (!value || !value[0]) {
        for (int i = 0; dirs[i]; i++) {
            char path[PATH_MAX];
            FILE *fp;

            snprintf(path, sizeof(path), "%s/%s", dirs[i],
                     "browser_headless_timer_pump_progress_limit.txt");
            fp = fopen(path, "r");
            if (!fp) {
                continue;
            }

            if (fgets(file_value, sizeof(file_value), fp)) {
                file_value[strcspn(file_value, "\r\n")] = 0;
            } else {
                file_value[0] = 0;
            }
            fclose(fp);

            if (file_value[0]) {
                value = file_value;
                source = "browser_headless_timer_pump_progress_limit.txt";
                break;
            }
        }
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

static bool xemu_headless_browser_timer_pump_progress_budget_available(
    uint64_t progress_events)
{
    int64_t limit = xemu_headless_browser_timer_pump_progress_limit();

    return limit < 0 || progress_events < (uint64_t)limit;
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

static void xemu_headless_pump_browser_timers(void)
{
#if defined(CONFIG_XEMU_BROWSER_BOOT) && defined(__EMSCRIPTEN__)
    static uint64_t progress_events;
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

    xemu_headless_trace_browser_timer_pump_gate(ready);
    if (!ready) {
        return;
    }

    if (!xemu_headless_browser_timer_pump_progress_budget_available(
            progress_events)) {
        xemu_headless_trace_browser_timer_pump_progress_limit(progress_events);
        return;
    }

    if (!bql_try_lock()) {
        xemu_headless_trace_browser_timer_pump_bql_busy();
        return;
    }

    virtual_now_before = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_before =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_before = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_before = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    xemu_headless_trace_browser_timer_pump_step("before", false);
    progress = qemu_clock_run_timers_with_attrs_limit(
        QEMU_CLOCK_VIRTUAL, 0, 0, 1);
    if (progress) {
        progress_events++;
    }
    xemu_headless_trace_browser_timer_pump_step("after", progress);
    virtual_now_after = qemu_clock_get_ns(QEMU_CLOCK_VIRTUAL);
    virtual_deadline_after =
        qemu_clock_deadline_ns_all(QEMU_CLOCK_VIRTUAL, QEMU_TIMER_ATTR_ALL);
    virtual_has_timers_after = qemu_clock_has_timers(QEMU_CLOCK_VIRTUAL);
    virtual_expired_after = qemu_clock_expired(QEMU_CLOCK_VIRTUAL);
    xemu_xbe_boot_trace_observe_main_loop_timers(
        "browser-headless-host-pump-bounded",
        0, 0, virtual_now_before, virtual_deadline_before,
        virtual_has_timers_before, virtual_expired_before, progress,
        virtual_now_after, virtual_deadline_after, virtual_has_timers_after,
        virtual_expired_after);
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
    xemu_boot_trace_mark("b0 thread=qemu-main started");
    qemu_init(g_argc, g_argv);
    xemu_headless_vblank_start();
    exit_status = qemu_main_loop();
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
    int64_t timeout_ms;
    int64_t start_us;
    const char *reason = "shutdown";

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
    return exit_status;
}
