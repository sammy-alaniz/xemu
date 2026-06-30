#!/usr/bin/env python3
"""Compare native/browser B6 PFIFO/PGRAPH command-stream diagnostics."""

import argparse
import sys
from dataclasses import dataclass


@dataclass
class StreamSummary:
    label: str
    notify_error_count: int = 0
    notify_clear_count: int = 0
    latest_notify_error: str = ""
    latest_notify_clear: str = ""
    latest_pfifo_window: str = ""
    latest_pgraph_method_window: str = ""
    latest_kernel_loop: str = ""
    xbe_executed: bool = False
    pfifo_window_count: int = 0
    pgraph_method_window_count: int = 0
    last_notify_error_trapped_data: str = "none"
    last_notify_clear_trapped_data: str = "none"
    last_notify_clear_dma_get: str = "none"
    last_notify_clear_dma_put: str = "none"
    last_notify_clear_waiting_nop_after: str = "unknown"
    last_notify_clear_pending_after: str = "unknown"
    last_pfifo_window_op: str = "none"
    last_pfifo_window_dma_get: str = "none"
    last_pfifo_window_dma_put: str = "none"
    last_pfifo_window_method: str = "none"
    last_pfifo_window_parameter: str = "none"
    last_pgraph_window_phase: str = "none"
    last_pgraph_window_dma_get: str = "none"
    last_pgraph_window_dma_put: str = "none"
    last_pgraph_window_method: str = "none"
    last_pgraph_window_parameter: str = "none"
    latest_loop_start_pc: str = "none"
    latest_loop_next_pc: str = "none"
    latest_loop_kind: str = "none"
    latest_loop_wait_source: str = "none"
    latest_loop_wait_op: str = "none"
    latest_loop_wait_seq: str = "none"
    latest_loop_dma_get: str = "none"
    latest_loop_dma_put: str = "none"
    latest_loop_pgraph_pending: str = "unknown"
    latest_loop_waiting_nop: str = "unknown"


def stream_idle(summary):
    return (
        summary.last_pfifo_window_op == "pusher-empty"
        and summary.last_pfifo_window_dma_get != "none"
        and summary.last_pfifo_window_dma_get == summary.last_pfifo_window_dma_put
    )


def command_stream_aligned(native, browser):
    return (
        native.notify_clear_count == browser.notify_clear_count
        and native.last_notify_clear_trapped_data == browser.last_notify_clear_trapped_data
        and native.last_notify_clear_dma_get == browser.last_notify_clear_dma_get
        and native.last_notify_clear_dma_put == browser.last_notify_clear_dma_put
        and native.last_notify_clear_waiting_nop_after == "no"
        and browser.last_notify_clear_waiting_nop_after == "no"
        and native.last_notify_clear_pending_after == "0x00000000"
        and browser.last_notify_clear_pending_after == "0x00000000"
        and stream_idle(native)
        and stream_idle(browser)
        and native.last_pfifo_window_dma_get == browser.last_pfifo_window_dma_get
        and native.last_pfifo_window_dma_put == browser.last_pfifo_window_dma_put
        and native.last_pgraph_window_dma_get == browser.last_pgraph_window_dma_get
        and native.last_pgraph_window_dma_put == browser.last_pgraph_window_dma_put
        and native.last_pgraph_window_method == browser.last_pgraph_window_method
        and native.last_pgraph_window_parameter == browser.last_pgraph_window_parameter
    )


def fail(reason, **fields):
    parts = [f"PGRAPH_COMMAND_STREAM_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def line_value(line, key, default=""):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return default


def parse_log(path, label, context):
    summary = StreamSummary(label=label)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for raw_line in log:
                line = raw_line.rstrip("\n")
                if context and f"context={context}" not in line:
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=xbe-executed "):
                    summary.xbe_executed = True
                    continue
                if line.startswith("BOOT_MARK b6 pgraph=notify-error "):
                    summary.notify_error_count += 1
                    summary.latest_notify_error = line
                    summary.last_notify_error_trapped_data = line_value(
                        line, "trapped_data", "none"
                    )
                    continue
                if line.startswith("BOOT_MARK b6 pgraph=notify-clear "):
                    summary.notify_clear_count += 1
                    summary.latest_notify_clear = line
                    summary.last_notify_clear_trapped_data = line_value(
                        line, "trapped_data", "none"
                    )
                    summary.last_notify_clear_dma_get = line_value(
                        line, "dma_get", "none"
                    )
                    summary.last_notify_clear_dma_put = line_value(
                        line, "dma_put", "none"
                    )
                    summary.last_notify_clear_waiting_nop_after = line_value(
                        line, "waiting_nop_after", "unknown"
                    )
                    summary.last_notify_clear_pending_after = line_value(
                        line, "pending_after", "unknown"
                    )
                    continue
                if line.startswith("BOOT_MARK b6 pfifo=window "):
                    summary.pfifo_window_count += 1
                    summary.latest_pfifo_window = line
                    summary.last_pfifo_window_op = line_value(line, "op", "none")
                    summary.last_pfifo_window_dma_get = line_value(
                        line, "dma_get", "none"
                    )
                    summary.last_pfifo_window_dma_put = line_value(
                        line, "dma_put", "none"
                    )
                    summary.last_pfifo_window_method = line_value(
                        line, "method", "none"
                    )
                    summary.last_pfifo_window_parameter = line_value(
                        line, "parameter", "none"
                    )
                    continue
                if line.startswith("BOOT_MARK b6 pgraph=method-window "):
                    summary.pgraph_method_window_count += 1
                    summary.latest_pgraph_method_window = line
                    summary.last_pgraph_window_phase = line_value(
                        line, "phase", "none"
                    )
                    summary.last_pgraph_window_dma_get = line_value(
                        line, "dma_get", "none"
                    )
                    summary.last_pgraph_window_dma_put = line_value(
                        line, "dma_put", "none"
                    )
                    summary.last_pgraph_window_method = line_value(
                        line, "method", "none"
                    )
                    summary.last_pgraph_window_parameter = line_value(
                        line, "parameter", "none"
                    )
                    continue
                if line.startswith("BOOT_MARK b6 dashboard=kernel-loop-probe "):
                    summary.latest_kernel_loop = line
                    summary.latest_loop_start_pc = line_value(line, "start_pc", "none")
                    summary.latest_loop_next_pc = line_value(line, "next_pc", "none")
                    summary.latest_loop_kind = line_value(line, "loop_kind", "none")
                    summary.latest_loop_wait_source = line_value(
                        line, "nv2a_wait_source", "none"
                    )
                    summary.latest_loop_wait_op = line_value(
                        line, "nv2a_wait_op", "none"
                    )
                    summary.latest_loop_wait_seq = line_value(
                        line, "nv2a_wait_seq", "none"
                    )
                    summary.latest_loop_dma_get = line_value(
                        line, "nv2a_dma_get", "none"
                    )
                    summary.latest_loop_dma_put = line_value(
                        line, "nv2a_dma_put", "none"
                    )
                    summary.latest_loop_pgraph_pending = line_value(
                        line, "nv2a_pgraph_pending", "unknown"
                    )
                    summary.latest_loop_waiting_nop = line_value(
                        line, "nv2a_waiting_nop", "unknown"
                    )
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc
    return summary


def divergence_for(native, browser):
    if browser.notify_clear_count > native.notify_clear_count:
        return "browser-extra-notify-clear"
    if browser.notify_clear_count < native.notify_clear_count:
        return "native-extra-notify-clear"
    if browser.last_notify_clear_trapped_data != native.last_notify_clear_trapped_data:
        return "notify-trapped-data-mismatch"
    if browser.last_notify_clear_dma_get != native.last_notify_clear_dma_get:
        return "notify-dma-get-mismatch"
    if browser.last_pfifo_window_dma_get != native.last_pfifo_window_dma_get:
        return "pfifo-window-dma-get-mismatch"
    if browser.last_pgraph_window_dma_get != native.last_pgraph_window_dma_get:
        return "pgraph-window-dma-get-mismatch"
    if browser.latest_loop_start_pc != native.latest_loop_start_pc:
        return "post-command-loop-mismatch"
    return "none"


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native/browser PFIFO/PGRAPH B6 diagnostics without "
            "reading or dumping proprietary asset bytes."
        )
    )
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args()

    try:
        native = parse_log(args.native_log, "native", args.native_context)
        browser = parse_log(args.browser_log, "browser", args.browser_context)
    except RuntimeError as exc:
        return fail(str(exc).replace(" ", "-"))

    if native.notify_clear_count == 0:
        return fail("missing-native-notify-clear", native_log=args.native_log)
    if browser.notify_clear_count == 0:
        return fail("missing-browser-notify-clear", browser_log=args.browser_log)

    divergence = divergence_for(native, browser)
    fields = {
        "divergence": divergence,
        "command_stream_aligned": "yes" if command_stream_aligned(native, browser) else "no",
        "native_stream_idle": "yes" if stream_idle(native) else "no",
        "browser_stream_idle": "yes" if stream_idle(browser) else "no",
        "native_notify_error": native.notify_error_count,
        "native_notify_clear": native.notify_clear_count,
        "native_last_trapped_data": native.last_notify_clear_trapped_data,
        "native_last_dma_get": native.last_notify_clear_dma_get,
        "native_last_dma_put": native.last_notify_clear_dma_put,
        "native_waiting_nop_after": native.last_notify_clear_waiting_nop_after,
        "native_pending_after": native.last_notify_clear_pending_after,
        "native_pfifo_window": native.pfifo_window_count,
        "native_pfifo_window_op": native.last_pfifo_window_op,
        "native_pfifo_window_dma_get": native.last_pfifo_window_dma_get,
        "native_pfifo_window_dma_put": native.last_pfifo_window_dma_put,
        "native_pfifo_window_method": native.last_pfifo_window_method,
        "native_pfifo_window_parameter": native.last_pfifo_window_parameter,
        "native_pgraph_method_window": native.pgraph_method_window_count,
        "native_pgraph_window_phase": native.last_pgraph_window_phase,
        "native_pgraph_window_dma_get": native.last_pgraph_window_dma_get,
        "native_pgraph_window_dma_put": native.last_pgraph_window_dma_put,
        "native_pgraph_window_method": native.last_pgraph_window_method,
        "native_pgraph_window_parameter": native.last_pgraph_window_parameter,
        "native_loop_start_pc": native.latest_loop_start_pc,
        "native_loop_next_pc": native.latest_loop_next_pc,
        "native_loop_kind": native.latest_loop_kind,
        "native_loop_wait_source": native.latest_loop_wait_source,
        "native_loop_wait_op": native.latest_loop_wait_op,
        "native_loop_wait_seq": native.latest_loop_wait_seq,
        "native_loop_dma_get": native.latest_loop_dma_get,
        "native_loop_dma_put": native.latest_loop_dma_put,
        "native_loop_pgraph_pending": native.latest_loop_pgraph_pending,
        "native_loop_waiting_nop": native.latest_loop_waiting_nop,
        "browser_notify_error": browser.notify_error_count,
        "browser_notify_clear": browser.notify_clear_count,
        "browser_last_trapped_data": browser.last_notify_clear_trapped_data,
        "browser_last_dma_get": browser.last_notify_clear_dma_get,
        "browser_last_dma_put": browser.last_notify_clear_dma_put,
        "browser_waiting_nop_after": browser.last_notify_clear_waiting_nop_after,
        "browser_pending_after": browser.last_notify_clear_pending_after,
        "browser_pfifo_window": browser.pfifo_window_count,
        "browser_pfifo_window_op": browser.last_pfifo_window_op,
        "browser_pfifo_window_dma_get": browser.last_pfifo_window_dma_get,
        "browser_pfifo_window_dma_put": browser.last_pfifo_window_dma_put,
        "browser_pfifo_window_method": browser.last_pfifo_window_method,
        "browser_pfifo_window_parameter": browser.last_pfifo_window_parameter,
        "browser_pgraph_method_window": browser.pgraph_method_window_count,
        "browser_pgraph_window_phase": browser.last_pgraph_window_phase,
        "browser_pgraph_window_dma_get": browser.last_pgraph_window_dma_get,
        "browser_pgraph_window_dma_put": browser.last_pgraph_window_dma_put,
        "browser_pgraph_window_method": browser.last_pgraph_window_method,
        "browser_pgraph_window_parameter": browser.last_pgraph_window_parameter,
        "browser_loop_start_pc": browser.latest_loop_start_pc,
        "browser_loop_next_pc": browser.latest_loop_next_pc,
        "browser_loop_kind": browser.latest_loop_kind,
        "browser_loop_wait_source": browser.latest_loop_wait_source,
        "browser_loop_wait_op": browser.latest_loop_wait_op,
        "browser_loop_wait_seq": browser.latest_loop_wait_seq,
        "browser_loop_dma_get": browser.latest_loop_dma_get,
        "browser_loop_dma_put": browser.latest_loop_dma_put,
        "browser_loop_pgraph_pending": browser.latest_loop_pgraph_pending,
        "browser_loop_waiting_nop": browser.latest_loop_waiting_nop,
        "native_xbe_executed": "yes" if native.xbe_executed else "no",
        "browser_xbe_executed": "yes" if browser.xbe_executed else "no",
        "native_log": args.native_log,
        "browser_log": args.browser_log,
    }
    parts = ["PGRAPH_COMMAND_STREAM_COMPARE result=pass"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
