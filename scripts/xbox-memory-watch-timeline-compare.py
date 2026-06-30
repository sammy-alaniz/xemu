#!/usr/bin/env python3
"""Compare B6 watched-memory timing between native and browser logs."""

import argparse
import re
import sys
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')
WATCH_TICK_UNIT = 0x2710
DEFAULT_WATCH_PHYS = 0x0003A890


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def parse_int(value):
    if not value or value == "none":
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def hex32(value):
    if value is None:
        return "none"
    return f"0x{value:08x}"


def tick_count(value):
    if value is None or value % WATCH_TICK_UNIT != 0:
        return None
    return value // WATCH_TICK_UNIT


def tick_text(value):
    return "none" if value is None else str(value)


def relation(native_value, browser_value):
    if native_value is None or browser_value is None:
        return "not-comparable"
    if native_value == browser_value:
        return "equal"
    if native_value > browser_value:
        return "browser-behind"
    return "browser-ahead"


def timer_relation(native_ticks, browser_ticks):
    if native_ticks is None or browser_ticks is None:
        return "not-comparable"
    if browser_ticks >= native_ticks:
        return "browser-reaches-native-shared-poll"
    return "browser-under-native-shared-poll"


@dataclass
class WatchEvent:
    line_no: int
    marker: dict
    value: int | None


@dataclass
class PollEvent:
    line_no: int
    marker: dict
    side: str
    value: int | None

    def edge(self):
        return (
            f"{self.marker.get('start_pc', 'none')}"
            f"->{self.marker.get('next_pc', 'none')}"
        )


@dataclass
class ParsedLog:
    label: str
    path: str
    install_results: list = field(default_factory=list)
    watch_events: list = field(default_factory=list)
    timer_samples: list = field(default_factory=list)
    shared_polls: list = field(default_factory=list)
    xbe_executed: list = field(default_factory=list)

    def focused_shared_polls(self):
        stream_idle = [
            event for event in self.shared_polls
            if event.marker.get("stream_idle") == "yes"
        ]
        if stream_idle:
            return stream_idle
        return list(self.shared_polls)


def context_matches(marker, context):
    return not context or marker.get("context") == context


def side_mem_matches(marker, side, watch_phys):
    phys = parse_int(marker.get(f"{side}_mem_phys", "none"))
    return (
        marker.get(f"{side}_mem_value_read") == "yes" and
        phys == watch_phys
    )


def parse_log(path, label, context, watch_phys):
    parsed = ParsedLog(label=label, path=path)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not context_matches(marker, context):
                    continue

                if "BOOT_MARK b6 memory-watch-install " in raw_line:
                    parsed.install_results.append(WatchEvent(
                        line_no, marker, None))
                    continue

                if "BOOT_MARK b6 memory-watch " in raw_line:
                    parsed.watch_events.append(WatchEvent(
                        line_no, marker, parse_int(marker.get("value"))))
                    continue

                if marker.get("main-loop") == "timers":
                    phys = parse_int(marker.get("memory_watch_phys", "none"))
                    if (phys == watch_phys and
                            marker.get("memory_watch_value_read") == "yes"):
                        parsed.timer_samples.append(WatchEvent(
                            line_no, marker,
                            parse_int(marker.get("memory_watch_value"))))
                    continue

                if marker.get("dashboard") == "kernel-loop-probe":
                    for side in ("start", "next"):
                        if side_mem_matches(marker, side, watch_phys):
                            parsed.shared_polls.append(PollEvent(
                                line_no, marker, side,
                                parse_int(marker.get(f"{side}_mem_value"))))
                    continue

                if marker.get("dashboard") == "xbe-executed":
                    parsed.xbe_executed.append(WatchEvent(
                        line_no, marker, None))
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc
    return parsed


def first_event(events):
    return events[0] if events else None


def last_event(events):
    return events[-1] if events else None


def max_value_event(events):
    valued = [event for event in events if event.value is not None]
    if not valued:
        return None
    return max(valued, key=lambda event: event.value)


def first_write(events):
    for event in events:
        if event.marker.get("access") == "write":
            return event
    return None


def last_write(events):
    for event in reversed(events):
        if event.marker.get("access") == "write":
            return event
    return None


def install_result(parsed):
    for event in parsed.install_results:
        result = event.marker.get("result")
        if result:
            return result
    return "none"


def add_event_fields(fields, prefix, key, event):
    marker = event.marker if event else {}
    value = event.value if event else None
    fields.update({
        f"{prefix}_{key}_line": event.line_no if event else 0,
        f"{prefix}_{key}_eip": marker.get("eip", "none"),
        f"{prefix}_{key}_value": hex32(value),
        f"{prefix}_{key}_ticks": tick_text(tick_count(value)),
        f"{prefix}_{key}_stream_idle": marker.get("stream_idle", "none"),
        f"{prefix}_{key}_wait_source": marker.get("nv2a_wait_source", "none"),
        f"{prefix}_{key}_wait_op": marker.get("nv2a_wait_op", "none"),
    })


def add_poll_fields(fields, prefix, key, event):
    marker = event.marker if event else {}
    value = event.value if event else None
    fields.update({
        f"{prefix}_{key}_line": event.line_no if event else 0,
        f"{prefix}_{key}_side": event.side if event else "none",
        f"{prefix}_{key}_edge": event.edge() if event else "none",
        f"{prefix}_{key}_eip": marker.get("eip", "none"),
        f"{prefix}_{key}_value": hex32(value),
        f"{prefix}_{key}_ticks": tick_text(tick_count(value)),
        f"{prefix}_{key}_wait_source": marker.get("nv2a_wait_source", "none"),
        f"{prefix}_{key}_wait_op": marker.get("nv2a_wait_op", "none"),
    })


def add_side_fields(fields, prefix, parsed):
    writes = [
        event for event in parsed.watch_events
        if event.marker.get("access") == "write"
    ]
    focused_polls = parsed.focused_shared_polls()
    first_poll = first_event(focused_polls)
    max_timer = max_value_event(parsed.timer_samples)
    last_timer = last_event(parsed.timer_samples)

    fields.update({
        f"{prefix}_log": parsed.path,
        f"{prefix}_watch_install": install_result(parsed),
        f"{prefix}_watch_access_events": len(parsed.watch_events),
        f"{prefix}_watch_write_events": len(writes),
        f"{prefix}_timer_watch_samples": len(parsed.timer_samples),
        f"{prefix}_shared_poll_events": len(parsed.shared_polls),
        f"{prefix}_focused_shared_poll_events": len(focused_polls),
        f"{prefix}_xbe_executed": "yes" if parsed.xbe_executed else "no",
    })
    add_event_fields(fields, prefix, "first_watch_write",
                     first_write(parsed.watch_events))
    add_event_fields(fields, prefix, "last_watch_write",
                     last_write(parsed.watch_events))
    add_event_fields(fields, prefix, "max_timer_watch", max_timer)
    add_event_fields(fields, prefix, "last_timer_watch", last_timer)
    add_poll_fields(fields, prefix, "first_shared_poll", first_poll)


def divergence_for(native, browser):
    if browser.xbe_executed:
        return "browser-dashboard-executed"
    native_polls = native.focused_shared_polls()
    browser_polls = browser.focused_shared_polls()
    if not native_polls:
        return "missing-native-shared-poll"
    if not browser_polls:
        return "missing-browser-shared-poll"

    native_ticks = tick_count(native_polls[0].value)
    browser_ticks = tick_count(browser_polls[0].value)
    if native_ticks is not None and browser_ticks is not None:
        if native_ticks > browser_ticks:
            return "browser-shared-poll-before-watch-catchup"
        if native_ticks == browser_ticks:
            return "shared-poll-equal"
        return "browser-shared-poll-ahead"

    native_value = native_polls[0].value
    browser_value = browser_polls[0].value
    if native_value != browser_value:
        return "shared-poll-value-mismatch"
    return "shared-poll-equal"


def fail(reason, **fields):
    parts = [f"MEMORY_WATCH_TIMELINE_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    parser.add_argument("--watch-phys", default=f"0x{DEFAULT_WATCH_PHYS:08x}")
    args = parser.parse_args()

    watch_phys = parse_int(args.watch_phys)
    if watch_phys is None:
        return fail("invalid-watch-phys", watch_phys=args.watch_phys)

    try:
        native = parse_log(args.native_log, "native", args.native_context,
                           watch_phys)
        browser = parse_log(args.browser_log, "browser", args.browser_context,
                            watch_phys)
    except RuntimeError as exc:
        return fail(str(exc).replace(" ", "-"))

    divergence = divergence_for(native, browser)
    native_first_poll = first_event(native.focused_shared_polls())
    browser_first_poll = first_event(browser.focused_shared_polls())
    native_poll_ticks = (
        tick_count(native_first_poll.value) if native_first_poll else None)
    browser_poll_ticks = (
        tick_count(browser_first_poll.value) if browser_first_poll else None)
    browser_max_timer = max_value_event(browser.timer_samples)
    browser_max_timer_ticks = (
        tick_count(browser_max_timer.value) if browser_max_timer else None)

    fields = {
        "result": "pass",
        "divergence": divergence,
        "watch_phys": f"0x{watch_phys:08x}",
        "watch_tick_unit": f"0x{WATCH_TICK_UNIT:08x}",
        "shared_poll_tick_relation": relation(
            native_poll_ticks, browser_poll_ticks),
        "shared_poll_tick_delta": tick_text(
            None if native_poll_ticks is None or browser_poll_ticks is None
            else native_poll_ticks - browser_poll_ticks),
        "browser_timer_max_relation": timer_relation(
            native_poll_ticks, browser_max_timer_ticks),
    }
    add_side_fields(fields, "native", native)
    add_side_fields(fields, "browser", browser)

    parts = ["MEMORY_WATCH_TIMELINE_COMPARE"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
