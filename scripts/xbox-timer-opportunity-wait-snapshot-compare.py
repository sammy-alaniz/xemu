#!/usr/bin/env python3
"""Compare timer-opportunity wait snapshots with nearby PFIFO publications."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value: str) -> str:
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_fields(line: str) -> dict[str, str]:
    return {key: parse_value(value) for key, value in FIELD_RE.findall(line)}


def compact_values(events: list[Event], key: str) -> str:
    values: list[str] = []
    for event in events:
        value = event.fields.get(key, "none")
        if value not in values:
            values.append(value)
    return ",".join(values) if values else "none"


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def field(event: Event | None, key: str, default: str = "none") -> str:
    if event is None:
        return default
    return event.fields.get(key, default)


def event_line(event: Event | None) -> str:
    return str(event.line_no) if event is not None else "0"


def line_delta(left: Event | None, right: Event | None) -> str:
    if left is None or right is None:
        return "none"
    return str(right.line_no - left.line_no)


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]


@dataclass
class ParsedLog:
    path: Path
    timer_opportunities: list[Event]
    pfifo_windows: list[Event]


def read_log(path: Path, context: str) -> ParsedLog:
    opportunities: list[Event] = []
    pfifo_windows: list[Event] = []

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            fields = parse_fields(line)
            if not context_matches(fields, context):
                continue
            if fields.get("headless") == "timer-opportunity":
                opportunities.append(Event(line_no, "timer-opportunity", fields))
                continue
            if fields.get("pfifo") == "window":
                pfifo_windows.append(Event(line_no, "pfifo-window", fields))

    return ParsedLog(
        path=path,
        timer_opportunities=opportunities,
        pfifo_windows=pfifo_windows,
    )


def previous_event(events: list[Event], line_no: int) -> Event | None:
    previous: Event | None = None
    for event in events:
        if event.line_no >= line_no:
            break
        previous = event
    return previous


def next_event(events: list[Event], line_no: int) -> Event | None:
    for event in events:
        if event.line_no > line_no:
            return event
    return None


def count_where(events: list[Event], key: str, expected: str) -> int:
    return sum(1 for event in events if event.fields.get(key) == expected)


def divergence(parsed: ParsedLog) -> str:
    opportunities = parsed.timer_opportunities
    if not opportunities:
        return "missing-timer-opportunity"

    selected_pfifo = [
        event for event in opportunities
        if event.fields.get("wait_source") == "pfifo-window"
    ]
    if selected_pfifo:
        if any(event.fields.get("wait_op") == "pusher-empty"
               for event in selected_pfifo):
            return "selected-pfifo-window-empty"
        return "selected-pfifo-window-nonempty"

    if any(previous_event(parsed.pfifo_windows, event.line_no)
           for event in opportunities):
        return "pfifo-window-published-but-not-selected"

    if any(next_event(parsed.pfifo_windows, event.line_no)
           for event in opportunities):
        return "no-pfifo-window-published-before-opportunities"

    return "missing-pfifo-window-publication"


def emit(parsed: ParsedLog) -> int:
    opportunities = parsed.timer_opportunities
    first_opportunity = opportunities[0] if opportunities else None
    last_opportunity = opportunities[-1] if opportunities else None
    first_previous_pfifo = (
        previous_event(parsed.pfifo_windows, first_opportunity.line_no)
        if first_opportunity else None
    )
    first_next_pfifo = (
        next_event(parsed.pfifo_windows, first_opportunity.line_no)
        if first_opportunity else None
    )
    last_previous_pfifo = (
        previous_event(parsed.pfifo_windows, last_opportunity.line_no)
        if last_opportunity else None
    )
    last_next_pfifo = (
        next_event(parsed.pfifo_windows, last_opportunity.line_no)
        if last_opportunity else None
    )
    opportunities_with_previous = sum(
        1 for event in opportunities
        if previous_event(parsed.pfifo_windows, event.line_no) is not None
    )
    opportunities_with_next = sum(
        1 for event in opportunities
        if next_event(parsed.pfifo_windows, event.line_no) is not None
    )
    div = divergence(parsed)
    result = "fail" if div.startswith("missing-") else "pass"

    parts = [
        "TIMER_OPPORTUNITY_WAIT_SNAPSHOT_COMPARE",
        f"result={result}",
        f"divergence={div}",
        f"timer_opportunities={len(opportunities)}",
        f"pfifo_window_publications={len(parsed.pfifo_windows)}",
        f"opportunities_with_previous_pfifo={opportunities_with_previous}",
        f"opportunities_with_next_pfifo={opportunities_with_next}",
        f"opportunity_wait_sources={compact_values(opportunities, 'wait_source')}",
        f"opportunity_wait_ops={compact_values(opportunities, 'wait_op')}",
        f"opportunity_blockers={compact_values(opportunities, 'pfifo_empty_blocker')}",
        f"opportunity_reasons={compact_values(opportunities, 'reason')}",
        f"opportunity_ready={count_where(opportunities, 'ready', 'yes')}",
        f"opportunity_expired={count_where(opportunities, 'virtual_expired', 'yes')}",
        f"first_opportunity_line={event_line(first_opportunity)}",
        f"first_opportunity_seq={field(first_opportunity, 'seq')}",
        f"first_opportunity_eip={field(first_opportunity, 'eip')}",
        f"first_opportunity_wait_source={field(first_opportunity, 'wait_source')}",
        f"first_opportunity_wait_op={field(first_opportunity, 'wait_op')}",
        f"first_opportunity_blocker={field(first_opportunity, 'pfifo_empty_blocker')}",
        f"first_opportunity_virtual_expired={field(first_opportunity, 'virtual_expired')}",
        f"first_opportunity_watch_value={field(first_opportunity, 'memory_watch_value')}",
        f"first_previous_pfifo_line={event_line(first_previous_pfifo)}",
        f"first_previous_pfifo_delta={line_delta(first_previous_pfifo, first_opportunity)}",
        f"first_previous_pfifo_seq={field(first_previous_pfifo, 'seq')}",
        f"first_previous_pfifo_op={field(first_previous_pfifo, 'op')}",
        f"first_previous_pfifo_dma_get={field(first_previous_pfifo, 'dma_get')}",
        f"first_previous_pfifo_dma_put={field(first_previous_pfifo, 'dma_put')}",
        f"first_previous_pfifo_available={field(first_previous_pfifo, 'available')}",
        f"first_next_pfifo_line={event_line(first_next_pfifo)}",
        f"first_next_pfifo_delta={line_delta(first_opportunity, first_next_pfifo)}",
        f"first_next_pfifo_seq={field(first_next_pfifo, 'seq')}",
        f"first_next_pfifo_op={field(first_next_pfifo, 'op')}",
        f"first_next_pfifo_dma_get={field(first_next_pfifo, 'dma_get')}",
        f"first_next_pfifo_dma_put={field(first_next_pfifo, 'dma_put')}",
        f"first_next_pfifo_available={field(first_next_pfifo, 'available')}",
        f"last_opportunity_line={event_line(last_opportunity)}",
        f"last_opportunity_seq={field(last_opportunity, 'seq')}",
        f"last_opportunity_eip={field(last_opportunity, 'eip')}",
        f"last_opportunity_wait_source={field(last_opportunity, 'wait_source')}",
        f"last_opportunity_wait_op={field(last_opportunity, 'wait_op')}",
        f"last_opportunity_blocker={field(last_opportunity, 'pfifo_empty_blocker')}",
        f"last_opportunity_virtual_expired={field(last_opportunity, 'virtual_expired')}",
        f"last_opportunity_watch_value={field(last_opportunity, 'memory_watch_value')}",
        f"last_previous_pfifo_line={event_line(last_previous_pfifo)}",
        f"last_previous_pfifo_delta={line_delta(last_previous_pfifo, last_opportunity)}",
        f"last_previous_pfifo_seq={field(last_previous_pfifo, 'seq')}",
        f"last_previous_pfifo_op={field(last_previous_pfifo, 'op')}",
        f"last_next_pfifo_line={event_line(last_next_pfifo)}",
        f"last_next_pfifo_delta={line_delta(last_opportunity, last_next_pfifo)}",
        f"last_next_pfifo_seq={field(last_next_pfifo, 'seq')}",
        f"last_next_pfifo_op={field(last_next_pfifo, 'op')}",
        f"log={parsed.path}",
    ]
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Pair browser timer-opportunity wait snapshots with nearby "
            "PFIFO-window publications."
        )
    )
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args()

    if not args.browser_log.is_file():
        print(
            "TIMER_OPPORTUNITY_WAIT_SNAPSHOT_COMPARE result=fail "
            f"reason=missing-browser-log path={args.browser_log}",
            file=sys.stderr,
        )
        return 1

    parsed = read_log(args.browser_log, args.browser_context)
    return emit(parsed)


if __name__ == "__main__":
    raise SystemExit(main())
