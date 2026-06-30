#!/usr/bin/env python3
"""Compare native/browser B6 post-service memory-poll behavior."""

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')
MEMORY_POLL_TICK_UNIT = 0x2710


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def bool_word(value):
    return "yes" if value else "no"


def parse_int(value):
    if not value or value == "none":
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def tick_count(value):
    parsed = parse_int(value)
    if parsed is None or parsed % MEMORY_POLL_TICK_UNIT != 0:
        return None
    return parsed // MEMORY_POLL_TICK_UNIT


def tick_text(value):
    return "none" if value is None else str(value)


def tick_relation(native_ticks, browser_ticks):
    if native_ticks is None or browser_ticks is None:
        return "not-comparable"
    if native_ticks == browser_ticks:
        return "equal"
    if native_ticks > browser_ticks:
        return "browser-behind"
    return "browser-ahead"


def marker_context_matches(marker, context):
    return not context or marker.get("context") == context


def is_stream_idle(marker):
    if marker.get("pfifo") == "window":
        if marker.get("op") != "pusher-empty":
            return False
        dma_get = marker.get("dma_get", "none")
        dma_put = marker.get("dma_put", "none")
        return dma_get != "none" and dma_get == dma_put

    if marker.get("pfifo") == "stream-idle-transition":
        return marker.get("wait_op") == "pusher-empty-transition"

    return False


def is_pfifo_empty_wait(marker):
    return (
        marker.get("nv2a_wait_source") == "pfifo-window"
        and marker.get("nv2a_wait_op") == "pusher-empty"
    )


def is_memory_read(marker, side):
    return marker.get(f"{side}_mem_value_read") == "yes"


def memory_signature(marker):
    for side in ("next", "start"):
        if is_memory_read(marker, side):
            return {
                "side": side,
                "kind": marker.get(f"{side}_mem_kind", "none"),
                "addr": marker.get(f"{side}_mem_addr", "none"),
                "region": marker.get(f"{side}_mem_region", "none"),
                "phys": marker.get(f"{side}_mem_phys", "none"),
                "value": marker.get(f"{side}_mem_value", "none"),
            }
    return {
        "side": "none",
        "kind": "none",
        "addr": "none",
        "region": "none",
        "phys": "none",
        "value": "none",
    }


def edge_key(marker):
    return (
        marker.get("start_pc", "none"),
        marker.get("next_pc", "none"),
        marker.get("tb_size", "none"),
        marker.get("tb_exit", "none"),
    )


def edge_text(edge):
    start, next_pc, _, _ = edge
    return f"{start}->{next_pc}"


def compact_edge(marker):
    if not marker:
        return "none"
    return f"{marker.get('start_pc', 'none')}->{marker.get('next_pc', 'none')}"


@dataclass
class Event:
    line_no: int
    marker: dict


@dataclass
class ParsedLog:
    label: str
    path: str
    stream_idle_events: list = field(default_factory=list)
    iret_after_events: list = field(default_factory=list)
    main_loop_timer_events: list = field(default_factory=list)
    loop_events: list = field(default_factory=list)
    xbe_executed: list = field(default_factory=list)

    def preferred_iret(self):
        pfifo_empty = [
            event for event in self.iret_after_events
            if is_pfifo_empty_wait(event.marker)
        ]
        preferred_returns = [
            event for event in pfifo_empty
            if event.marker.get("eip") == "0x80030e84"
        ]
        if preferred_returns:
            return preferred_returns[0]
        if pfifo_empty:
            return pfifo_empty[0]
        if self.iret_after_events:
            return self.iret_after_events[0]
        return None

    def first_stream_idle_line(self):
        if not self.stream_idle_events:
            return 0
        return self.stream_idle_events[0].line_no

    def focus_start_line(self):
        starts = []
        if self.first_stream_idle_line():
            starts.append(self.first_stream_idle_line())
        iret = self.preferred_iret()
        if iret:
            starts.append(iret.line_no)
        if starts:
            return max(starts)
        return 0

    def focus_loops(self):
        start = self.focus_start_line()
        if not start:
            return list(self.loop_events)
        return [event for event in self.loop_events if event.line_no > start]

    def first_loop_after_preferred_iret(self):
        iret = self.preferred_iret()
        if not iret:
            return None
        for event in self.loop_events:
            if event.line_no > iret.line_no:
                return event
        return None

    def memory_poll_events(self):
        return [
            event for event in self.focus_loops()
            if is_memory_read(event.marker, "next")
            or is_memory_read(event.marker, "start")
        ]

    def memory_polls_by_addr(self):
        by_addr = {}
        for event in self.memory_poll_events():
            sig = memory_signature(event.marker)
            if sig["addr"] == "none":
                continue
            by_addr.setdefault(sig["addr"], []).append((sig, event))
        return by_addr

    def top_edge(self):
        counts = Counter(edge_key(event.marker) for event in self.focus_loops())
        if not counts:
            return ("none", "none", "none", "none"), 0, None
        edge, count = counts.most_common(1)[0]
        for event in reversed(self.focus_loops()):
            if edge_key(event.marker) == edge:
                return edge, count, event
        return edge, count, None

    def top_memory_poll(self):
        counts = Counter(
            (
                memory_signature(event.marker)["side"],
                memory_signature(event.marker)["kind"],
                memory_signature(event.marker)["addr"],
                memory_signature(event.marker)["region"],
                memory_signature(event.marker)["value"],
            )
            for event in self.memory_poll_events()
        )
        if not counts:
            return ("none", "none", "none", "none", "none"), 0, None
        signature, count = counts.most_common(1)[0]
        for event in reversed(self.memory_poll_events()):
            current = memory_signature(event.marker)
            current_sig = (
                current["side"],
                current["kind"],
                current["addr"],
                current["region"],
                current["value"],
            )
            if current_sig == signature:
                return signature, count, event
        return signature, count, None

    def main_loop_timer_progress_events(self):
        return [
            event for event in self.main_loop_timer_events
            if event.marker.get("timer_progress") == "yes"
        ]

    def main_loop_timer_memory_watch_values(self):
        values = []
        for event in self.main_loop_timer_events:
            if event.marker.get("memory_watch_value_read") != "yes":
                continue
            value = parse_int(event.marker.get("memory_watch_value", "none"))
            if value is not None:
                values.append((value, event))
        return values


def parse_log(path, label, context):
    parsed = ParsedLog(label=label, path=path)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not marker_context_matches(marker, context):
                    continue

                if is_stream_idle(marker):
                    parsed.stream_idle_events.append(Event(line_no, marker))
                    continue

                if marker.get("main-loop") == "timers":
                    parsed.main_loop_timer_events.append(Event(line_no, marker))
                    continue

                if marker.get("cpu") == "iret" and marker.get("phase") == "after":
                    parsed.iret_after_events.append(Event(line_no, marker))
                    continue

                if marker.get("dashboard") == "kernel-loop-probe":
                    parsed.loop_events.append(Event(line_no, marker))
                    continue

                if marker.get("dashboard") == "xbe-executed":
                    parsed.xbe_executed.append(Event(line_no, marker))
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc
    return parsed


def fail(reason, **fields):
    parts = [f"POST_SERVICE_MEMORY_POLL_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def divergence_for(native, browser):
    if browser.xbe_executed:
        return "browser-dashboard-executed"
    if not native.focus_loops() and not browser.focus_loops():
        return "missing-focus-loop-samples"
    if not native.focus_loops():
        return "native-missing-focus-loop-samples"
    if not browser.focus_loops():
        return "browser-missing-focus-loop-samples"

    shared = shared_memory_mismatch(native, browser)
    if shared["addr"] != "none":
        return "shared-memory-poll-value-mismatch"

    native_edge, _, _ = native.top_edge()
    browser_edge, _, _ = browser.top_edge()
    if native_edge == browser_edge:
        return "same-top-edge"

    browser_mem = browser.top_memory_poll()[0]
    native_mem = native.top_memory_poll()[0]
    if browser_mem[0] != "none" and browser_mem != native_mem:
        return "browser-memory-poll-mismatch"

    return "post-service-edge-mismatch"


def shared_memory_mismatch(native, browser):
    native_by_addr = native.memory_polls_by_addr()
    browser_by_addr = browser.memory_polls_by_addr()

    for addr in browser_by_addr:
        if addr not in native_by_addr:
            continue
        browser_sig, browser_event = browser_by_addr[addr][0]
        native_sig, native_event = native_by_addr[addr][0]
        if browser_sig["value"] == native_sig["value"]:
            continue
        return {
            "addr": addr,
            "native_value": native_sig["value"],
            "browser_value": browser_sig["value"],
            "native_region": native_sig["region"],
            "browser_region": browser_sig["region"],
            "native_phys": native_sig["phys"],
            "browser_phys": browser_sig["phys"],
            "native_line": native_event.line_no,
            "browser_line": browser_event.line_no,
        }

    return {
        "addr": "none",
        "native_value": "none",
        "browser_value": "none",
        "native_region": "none",
        "browser_region": "none",
        "native_phys": "none",
        "browser_phys": "none",
        "native_line": 0,
        "browser_line": 0,
    }


def shared_tick_fields(shared):
    native_ticks = tick_count(shared["native_value"])
    browser_ticks = tick_count(shared["browser_value"])
    if shared["addr"] == "none":
        native_delta = None
    elif native_ticks is None or browser_ticks is None:
        native_delta = None
    else:
        native_delta = native_ticks - browser_ticks

    return {
        "shared_memory_poll_tick_unit": f"0x{MEMORY_POLL_TICK_UNIT:08x}",
        "native_shared_memory_poll_ticks": tick_text(native_ticks),
        "browser_shared_memory_poll_ticks": tick_text(browser_ticks),
        "shared_memory_poll_tick_delta": tick_text(native_delta),
        "shared_memory_poll_tick_relation": tick_relation(
            native_ticks, browser_ticks),
    }


def timer_watch_tick_fields(prefix, parsed):
    values = parsed.main_loop_timer_memory_watch_values()
    if values:
        max_value, max_event = max(values, key=lambda item: item[0])
        last_value, last_event = values[-1]
        max_text = f"0x{max_value:08x}"
        last_text = f"0x{last_value:08x}"
        max_ticks = tick_text(tick_count(max_text))
        last_ticks = tick_text(tick_count(last_text))
        max_line = max_event.line_no
        last_line = last_event.line_no
    else:
        max_text = "none"
        last_text = "none"
        max_ticks = "none"
        last_ticks = "none"
        max_line = 0
        last_line = 0

    return {
        f"{prefix}_main_loop_timer_events": len(parsed.main_loop_timer_events),
        f"{prefix}_main_loop_timer_progress_events": len(
            parsed.main_loop_timer_progress_events()),
        f"{prefix}_main_loop_timer_memory_watch_samples": len(values),
        f"{prefix}_main_loop_timer_max_memory_watch_value": max_text,
        f"{prefix}_main_loop_timer_max_memory_watch_ticks": max_ticks,
        f"{prefix}_main_loop_timer_max_memory_watch_line": max_line,
        f"{prefix}_main_loop_timer_last_memory_watch_value": last_text,
        f"{prefix}_main_loop_timer_last_memory_watch_ticks": last_ticks,
        f"{prefix}_main_loop_timer_last_memory_watch_line": last_line,
    }


def add_side_fields(fields, prefix, parsed):
    preferred_iret = parsed.preferred_iret()
    first_loop_after_iret = parsed.first_loop_after_preferred_iret()
    top_edge, top_edge_count, top_event = parsed.top_edge()
    top_mem, top_mem_count, top_mem_event = parsed.top_memory_poll()
    top_marker = top_event.marker if top_event else {}
    top_mem_marker = top_mem_event.marker if top_mem_event else {}
    mem_sig = memory_signature(top_mem_marker) if top_mem_marker else memory_signature({})

    fields.update({
        f"{prefix}_stream_idle_count": len(parsed.stream_idle_events),
        f"{prefix}_first_stream_idle_line": parsed.first_stream_idle_line(),
        f"{prefix}_iret_after_count": len(parsed.iret_after_events),
        f"{prefix}_preferred_iret_line": preferred_iret.line_no if preferred_iret else 0,
        f"{prefix}_preferred_iret_eip": preferred_iret.marker.get("eip", "none") if preferred_iret else "none",
        f"{prefix}_focus_start_line": parsed.focus_start_line(),
        f"{prefix}_loop_samples": len(parsed.loop_events),
        f"{prefix}_focus_loop_samples": len(parsed.focus_loops()),
        f"{prefix}_xbe_executed": bool_word(bool(parsed.xbe_executed)),
        f"{prefix}_first_loop_after_iret": compact_edge(first_loop_after_iret.marker) if first_loop_after_iret else "none",
        f"{prefix}_top_edge": edge_text(top_edge),
        f"{prefix}_top_edge_count": top_edge_count,
        f"{prefix}_top_wait_source": top_marker.get("nv2a_wait_source", "none"),
        f"{prefix}_top_wait_op": top_marker.get("nv2a_wait_op", "none"),
        f"{prefix}_top_loop_kind": top_marker.get("loop_kind", "none"),
        f"{prefix}_top_interrupts_enabled": top_marker.get("interrupts_enabled", "none"),
        f"{prefix}_top_cpu_interrupt_request": top_marker.get("cpu_interrupt_request", "none"),
        f"{prefix}_top_pending_interrupt": top_marker.get("pending_interrupt", "none"),
        f"{prefix}_memory_poll_samples": len(parsed.memory_poll_events()),
        f"{prefix}_top_memory_poll_count": top_mem_count,
        f"{prefix}_top_memory_poll_side": mem_sig["side"],
        f"{prefix}_top_memory_poll_kind": mem_sig["kind"],
        f"{prefix}_top_memory_poll_addr": mem_sig["addr"],
        f"{prefix}_top_memory_poll_region": mem_sig["region"],
        f"{prefix}_top_memory_poll_phys": mem_sig["phys"],
        f"{prefix}_top_memory_poll_value": mem_sig["value"],
    })
    fields.update(timer_watch_tick_fields(prefix, parsed))


def main():
    parser = argparse.ArgumentParser()
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

    if not native.stream_idle_events:
        return fail("missing-native-stream-idle", native_log=args.native_log)
    if not browser.stream_idle_events:
        return fail("missing-browser-stream-idle", browser_log=args.browser_log)

    divergence = divergence_for(native, browser)
    shared = shared_memory_mismatch(native, browser)
    fields = {
        "result": "pass",
        "divergence": divergence,
        "shared_memory_poll_addr": shared["addr"],
        "native_shared_memory_poll_value": shared["native_value"],
        "browser_shared_memory_poll_value": shared["browser_value"],
        "native_shared_memory_poll_region": shared["native_region"],
        "browser_shared_memory_poll_region": shared["browser_region"],
        "native_shared_memory_poll_phys": shared["native_phys"],
        "browser_shared_memory_poll_phys": shared["browser_phys"],
        "native_shared_memory_poll_line": shared["native_line"],
        "browser_shared_memory_poll_line": shared["browser_line"],
        "native_log": args.native_log,
        "browser_log": args.browser_log,
    }
    fields.update(shared_tick_fields(shared))
    add_side_fields(fields, "native", native)
    add_side_fields(fields, "browser", browser)

    parts = ["POST_SERVICE_MEMORY_POLL_COMPARE"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
