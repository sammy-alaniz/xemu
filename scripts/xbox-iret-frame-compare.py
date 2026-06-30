#!/usr/bin/env python3
"""Compare B6 hard-IRQ service frames and protected-mode IRET returns."""

import argparse
import re
import sys


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def is_stream_idle(marker):
    return (
        marker.get("nv2a_wait_source") == "pfifo-window"
        and marker.get("nv2a_wait_op") == "pusher-empty"
    )


def load_log(path):
    service_after = []
    iret_pairs = []
    pending_iret_before = None

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line_no, line in enumerate(handle, 1):
                if not line.startswith("BOOT_MARK b6 "):
                    continue
                if " cpu=hard-irq-service " in line:
                    marker = parse_marker(line)
                    marker["line"] = line_no
                    if marker.get("phase") == "after":
                        service_after.append(marker)
                    continue
                if " cpu=iret " in line:
                    marker = parse_marker(line)
                    marker["line"] = line_no
                    if marker.get("phase") == "before":
                        pending_iret_before = marker
                    elif marker.get("phase") == "after" and pending_iret_before:
                        iret_pairs.append((pending_iret_before, marker))
                        pending_iret_before = None
    except OSError as exc:
        raise SystemExit(f"failed to read {path}: {exc}") from exc

    return {
        "service_after": service_after,
        "iret_pairs": iret_pairs,
    }


def latest_preferred(markers):
    idle = [marker for marker in markers if is_stream_idle(marker)]
    if idle:
        return idle[-1]
    if markers:
        return markers[-1]
    return None


def matching_iret_pair(service, pairs):
    if not service:
        return None

    service_hash = service.get("stack_hash")
    matches = [
        pair for pair in pairs
        if pair[0].get("stack_hash") == service_hash and is_stream_idle(pair[0])
    ]
    if matches:
        return matches[-1]

    matches = [pair for pair in pairs if pair[0].get("stack_hash") == service_hash]
    if matches:
        return matches[-1]

    idle = [pair for pair in pairs if is_stream_idle(pair[0])]
    if idle:
        return idle[-1]
    if pairs:
        return pairs[-1]
    return None


def summarize(path):
    data = load_log(path)
    service = latest_preferred(data["service_after"])
    iret_pair = matching_iret_pair(service, data["iret_pairs"])
    if not service:
        return None, "missing-hard-irq-service-after"
    if not iret_pair:
        return None, "missing-iret-pair"
    before, after = iret_pair
    return {
        "log": path,
        "service": service,
        "iret_before": before,
        "iret_after": after,
    }, None


def field(summary, section, key, default="none"):
    if not summary:
        return default
    return summary[section].get(key, default)


def divergence(native, browser):
    if field(native, "service", "stack0") != field(browser, "service", "stack0"):
        return "interrupt-return-target-mismatch"
    if field(native, "iret_after", "eip") != field(browser, "iret_after", "eip"):
        return "iret-after-eip-mismatch"
    if field(native, "service", "stack2") != field(browser, "service", "stack2"):
        return "interrupt-return-flags-mismatch"
    if field(native, "service", "stack_hash") != field(browser, "service", "stack_hash"):
        return "interrupt-frame-stack-mismatch"
    return "none"


def emit_fail(reason, native_log, browser_log):
    print(
        "IRET_FRAME_COMPARE "
        f"result=fail reason={reason} "
        f"native_log={native_log} browser_log={browser_log}"
    )
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    args = parser.parse_args()

    native, native_reason = summarize(args.native_log)
    if native_reason:
        return emit_fail(f"native-{native_reason}", args.native_log, args.browser_log)

    browser, browser_reason = summarize(args.browser_log)
    if browser_reason:
        return emit_fail(f"browser-{browser_reason}", args.native_log, args.browser_log)

    diff = divergence(native, browser)
    print(
        "IRET_FRAME_COMPARE "
        f"result=pass divergence={diff} "
        f"native_service_line={field(native, 'service', 'line')} "
        f"browser_service_line={field(browser, 'service', 'line')} "
        f"native_service_eip={field(native, 'service', 'eip')} "
        f"browser_service_eip={field(browser, 'service', 'eip')} "
        f"native_irq_frame_eip={field(native, 'service', 'stack0')} "
        f"browser_irq_frame_eip={field(browser, 'service', 'stack0')} "
        f"native_irq_frame_cs={field(native, 'service', 'stack1')} "
        f"browser_irq_frame_cs={field(browser, 'service', 'stack1')} "
        f"native_irq_frame_eflags={field(native, 'service', 'stack2')} "
        f"browser_irq_frame_eflags={field(browser, 'service', 'stack2')} "
        f"native_iret_before_eip={field(native, 'iret_before', 'eip')} "
        f"browser_iret_before_eip={field(browser, 'iret_before', 'eip')} "
        f"native_iret_after_eip={field(native, 'iret_after', 'eip')} "
        f"browser_iret_after_eip={field(browser, 'iret_after', 'eip')} "
        f"native_iret_after_esp={field(native, 'iret_after', 'esp')} "
        f"browser_iret_after_esp={field(browser, 'iret_after', 'esp')} "
        f"native_stack_hash={field(native, 'service', 'stack_hash')} "
        f"browser_stack_hash={field(browser, 'service', 'stack_hash')} "
        f"native_log={args.native_log} browser_log={args.browser_log}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
