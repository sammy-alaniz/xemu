#!/usr/bin/env python3
"""Summarize browser headless timer-pump placement around PFIFO stream idle."""

import argparse
import re
import sys
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')
WATCH_TICK_UNIT = 0x2710


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


def text(value):
    return "none" if value is None else str(value)


def yes_no(value):
    return "yes" if value else "no"


def context_matches(marker, context):
    return not context or marker.get("context") == context


@dataclass
class Event:
    line_no: int
    marker: dict


@dataclass
class ParsedLog:
    path: str
    context: str
    diagnostic_ready_gates: list = field(default_factory=list)
    host_ready_gates: list = field(default_factory=list)
    pump_steps: list = field(default_factory=list)
    progress_steps: list = field(default_factory=list)
    timer_events: list = field(default_factory=list)
    stream_idle_transitions: list = field(default_factory=list)
    stream_idle_boundaries: list = field(default_factory=list)
    memory_writes: list = field(default_factory=list)


def parse_log(path, context):
    parsed = ParsedLog(path=path, context=context)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not context_matches(marker, context):
                    continue
                event = Event(line_no, marker)

                if "BOOT_MARK b6 headless=timer-pump-gate " in raw_line:
                    if marker.get("ready") == "yes":
                        parsed.diagnostic_ready_gates.append(event)
                    if marker.get("pump_ready") == "yes":
                        parsed.host_ready_gates.append(event)
                    continue

                if "BOOT_MARK b6 headless=timer-pump-step " in raw_line:
                    parsed.pump_steps.append(event)
                    if marker.get("phase") == "after" and marker.get("progress") == "yes":
                        parsed.progress_steps.append(event)
                    continue

                if marker.get("main-loop") == "timers":
                    parsed.timer_events.append(event)
                    continue

                if marker.get("pfifo") == "stream-idle-transition":
                    parsed.stream_idle_transitions.append(event)
                    continue

                if marker.get("pfifo") == "stream-idle-boundary":
                    parsed.stream_idle_boundaries.append(event)
                    continue

                if ("BOOT_MARK b6 memory-watch " in raw_line and
                        marker.get("access") == "write"):
                    parsed.memory_writes.append(event)
                    continue
    except OSError as exc:
        raise RuntimeError(f"browser log unreadable: {exc}") from exc
    return parsed


def first(events):
    return events[0] if events else None


def line(event):
    return event.line_no if event else 0


def marker_field(event, key):
    return event.marker.get(key, "none") if event else "none"


def value_field(event, key):
    return parse_int(event.marker.get(key)) if event else None


def classify(parsed):
    ready = first(parsed.diagnostic_ready_gates)
    host_ready = first(parsed.host_ready_gates)
    progress_step = first(parsed.progress_steps)
    timer = first(parsed.timer_events)
    transition = first(parsed.stream_idle_transitions)
    boundary = first(parsed.stream_idle_boundaries)

    if not ready and not host_ready:
        return "missing-ready-gate"
    if not transition:
        return "missing-stream-idle-transition"
    if not boundary:
        return "missing-stream-idle-boundary"
    if not progress_step and not timer:
        return "missing-progress-pump"

    pump_line = line(timer) or line(progress_step)
    ready_line = line(host_ready) or line(ready)

    if ready_line and ready_line < line(boundary) and pump_line > line(boundary):
        return "host-ready-before-boundary-pump-after-boundary"
    if pump_line < line(transition):
        return "pump-before-stream-idle-transition"
    if pump_line < line(boundary):
        return "pump-before-stream-idle-boundary"
    return "pump-after-stream-idle-boundary"


def relation_to_boundary(event, transition, boundary):
    if not event:
        return "missing"
    if transition and event.line_no < transition.line_no:
        return "before-stream-idle-transition"
    if boundary and event.line_no < boundary.line_no:
        return "before-stream-idle-boundary"
    return "after-stream-idle-boundary"


def add_event_fields(fields, prefix, event, transition, boundary):
    fields[f"{prefix}_line"] = str(line(event))
    fields[f"{prefix}_placement"] = relation_to_boundary(event, transition, boundary)
    fields[f"{prefix}_seq"] = marker_field(event, "seq")
    fields[f"{prefix}_eip"] = marker_field(event, "eip")
    fields[f"{prefix}_cpu_interrupt_request"] = marker_field(
        event, "cpu_interrupt_request")
    fields[f"{prefix}_wait_op"] = marker_field(event, "wait_op")
    fields[f"{prefix}_wait_dma_to_put"] = marker_field(event, "wait_dma_to_put")
    fields[f"{prefix}_nv2a_wait_op"] = marker_field(event, "nv2a_wait_op")
    fields[f"{prefix}_memory_watch_value"] = hex32(
        value_field(event, "memory_watch_value"))
    fields[f"{prefix}_memory_watch_ticks"] = text(
        tick_count(value_field(event, "memory_watch_value")))
    fields[f"{prefix}_write_value"] = hex32(value_field(event, "value"))
    fields[f"{prefix}_write_ticks"] = text(tick_count(value_field(event, "value")))


def emit(parsed):
    divergence = classify(parsed)
    result = "fail" if divergence.startswith("missing-") else "pass"
    ready = first(parsed.diagnostic_ready_gates)
    host_ready = first(parsed.host_ready_gates)
    progress_step = first(parsed.progress_steps)
    timer = first(parsed.timer_events)
    transition = first(parsed.stream_idle_transitions)
    boundary = first(parsed.stream_idle_boundaries)
    write = first(parsed.memory_writes)
    fields = {
        "result": result,
        "divergence": divergence,
        "context": parsed.context,
        "diagnostic_ready_gates": str(len(parsed.diagnostic_ready_gates)),
        "host_ready_gates": str(len(parsed.host_ready_gates)),
        "pump_steps": str(len(parsed.pump_steps)),
        "progress_pump_steps": str(len(parsed.progress_steps)),
        "timer_events": str(len(parsed.timer_events)),
        "stream_idle_transitions": str(len(parsed.stream_idle_transitions)),
        "stream_idle_boundaries": str(len(parsed.stream_idle_boundaries)),
        "memory_watch_writes": str(len(parsed.memory_writes)),
        "transition_line": str(line(transition)),
        "transition_eip": marker_field(transition, "eip"),
        "transition_cpu_interrupt_request": marker_field(
            transition, "cpu_interrupt_request"),
        "boundary_line": str(line(boundary)),
        "boundary_eip": marker_field(boundary, "eip"),
        "boundary_cpu_interrupt_request": marker_field(
            boundary, "cpu_interrupt_request"),
    }
    add_event_fields(fields, "first_diagnostic_ready", ready, transition, boundary)
    add_event_fields(fields, "first_host_ready", host_ready, transition, boundary)
    add_event_fields(fields, "first_progress_step", progress_step, transition, boundary)
    add_event_fields(fields, "first_timer", timer, transition, boundary)
    add_event_fields(fields, "first_memory_write", write, transition, boundary)
    fields["host_ready_before_boundary"] = yes_no(
        bool(host_ready and boundary and host_ready.line_no < boundary.line_no))
    fields["timer_before_boundary"] = yes_no(
        bool(timer and boundary and timer.line_no < boundary.line_no))
    fields["timer_after_boundary"] = yes_no(
        bool(timer and boundary and timer.line_no > boundary.line_no))
    fields["first_timer_watch_zero"] = yes_no(
        value_field(timer, "memory_watch_value") == 0)
    fields["first_memory_write_zero"] = yes_no(value_field(write, "value") == 0)
    fields["browser_log"] = parsed.path

    print(
        "HEADLESS_PUMP_PLACEMENT_COMPARE "
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )
    return 0 if result == "pass" else 1


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--context", default="browser-runtime")
    args = parser.parse_args(argv)

    try:
        parsed = parse_log(args.browser_log, args.context)
        return emit(parsed)
    except RuntimeError as exc:
        print(
            "HEADLESS_PUMP_PLACEMENT_COMPARE"
            f" result=fail reason={str(exc).replace(' ', '-')}"
            f" context={args.context}"
            f" browser_log={args.browser_log}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
