/*
 * Minimal xemu headless entry point for browser boot and smoke builds.
 */

#include "qemu/osdep.h"
#include "qemu/thread.h"
#include "qemu/main-loop.h"
#include "qemu/rcu.h"
#include "qemu-version.h"
#include "xemu-version.h"
#include "system/runstate.h"
#include "system/runstate-action.h"
#include "system/system.h"
#include "ui/xemu-browser-display.h"
#include "ui/xemu-settings.h"

#include <locale.h>

static QemuThread thread;
static int exit_status;
static bool qemu_exiting;

static int g_argc;
static char **g_argv;
static int64_t headless_boot_timeout_override_ms = -1;

static bool xemu_boot_trace_enabled(void)
{
    const char *value = getenv("XEMU_BOOT_TRACE");

    return value && value[0] && strcmp(value, "0");
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

static void *qemu_main_thread(void *opaque)
{
    xemu_boot_trace_mark("b0 thread=qemu-main started");
    qemu_init(g_argc, g_argv);
    xemu_browser_display_init();
    exit_status = qemu_main_loop();
    qatomic_set(&qemu_exiting, true);
    bql_unlock();
#ifdef XBOX
    qemu_mutex_unlock_main_loop();
#endif

    bql_lock();
    qemu_cleanup(exit_status);
    bql_unlock();

#if defined(__EMSCRIPTEN__) && defined(CONFIG_XEMU_BROWSER_BOOT)
    rcu_unregister_thread();
#endif

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

#ifdef CONFIG_OPENGL
    g_config.display.renderer = CONFIG_DISPLAY_RENDERER_OPENGL;
#else
    g_config.display.renderer = CONFIG_DISPLAY_RENDERER_NULL;
#endif
    g_config.general.updates.check = false;
    g_config.general.show_welcome = false;

    qemu_thread_create(&thread, "qemu_main", qemu_main_thread,
                       NULL, QEMU_THREAD_JOINABLE);
    xemu_boot_trace_mark("b0 thread=qemu-main created");

    timeout_ms = xemu_headless_boot_timeout_ms();
    start_us = g_get_monotonic_time();

    while (!qatomic_read(&qemu_exiting)) {
        int64_t elapsed_ms = (g_get_monotonic_time() - start_us) / 1000;

        if (timeout_ms > 0 && elapsed_ms >= timeout_ms) {
            reason = "timeout";
            qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
            break;
        }

        g_usleep(50000);
    }

    qemu_thread_join(&thread);
    if (xemu_boot_trace_enabled()) {
        fprintf(stderr,
                "BOOT_SMOKE_RESULT reason=%s elapsed_ms=%lld exit=%d\n",
                reason,
                (long long)((g_get_monotonic_time() - start_us) / 1000),
                exit_status);
    }
    return exit_status;
}
