#!/usr/bin/env python3
"""Classify why PFIFO-window publication starts after timer opportunities."""

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


def parse_int(value: str | None) -> int | None:
    if not value or value in {"none", "missing"}:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def hex32(value: int | None) -> str:
    if value is None:
        return "none"
    return f"0x{value & 0xffffffff:08x}"


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


def event_dma_get(event: Event | None) -> int | None:
    return parse_int(field(event, "dma_get"))


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]


@dataclass
class ParsedLog:
    path: Path
    timer_opportunities: list[Event]
    pfifo_progress: list[Event]
    pfifo_windows: list[Event]


def read_log(path: Path, context: str) -> ParsedLog:
    opportunities: list[Event] = []
    progress: list[Event] = []
    windows: list[Event] = []

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
            if fields.get("pfifo") == "progress":
                progress.append(Event(line_no, "pfifo-progress", fields))
                continue
            if fields.get("pfifo") == "window":
                windows.append(Event(line_no, "pfifo-window", fields))

    return ParsedLog(
        path=path,
        timer_opportunities=opportunities,
        pfifo_progress=progress,
        pfifo_windows=windows,
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


def events_between(events: list[Event], start_line: int, end_line: int) -> list[Event]:
    return [event for event in events if start_line < event.line_no < end_line]


def window_start_for(parsed: ParsedLog, override: int | None) -> int | None:
    if override is not None:
        return override
    for event in parsed.pfifo_windows:
        parsed_start = parse_int(field(event, "window_start"))
        if parsed_start is not None:
            return parsed_start
    return None


def not_published_reason(event: Event | None, window_start: int | None) -> str:
    if event is None:
        return "no-pfifo-producer-before-first-opportunity"
    dma_get = event_dma_get(event)
    if dma_get is None:
        return "missing-dma-get"
    if window_start is None:
        return "missing-window-start"
    if dma_get < window_start:
        return "dma-get-before-window-start"
    return "producer-at-or-after-window-start"


def published_reason(event: Event | None, window_start: int | None) -> str:
    if event is None:
        return "missing-pfifo-window-publication"
    dma_get = event_dma_get(event)
    if dma_get is None:
        return "missing-dma-get"
    if window_start is None:
        return "missing-window-start"
    if dma_get == window_start:
        return "window-start-reached"
    if dma_get > window_start:
        return "past-window-start"
    return "published-before-window-start"


def divergence(
    parsed: ParsedLog,
    first_opportunity: Event | None,
    last_opportunity: Event | None,
    first_progress: Event | None,
    first_window: Event | None,
    last_progress_before_window: Event | None,
    window_start: int | None,
) -> str:
    if first_opportunity is None:
        return "missing-timer-opportunity"
    if first_progress is None:
        return "missing-pfifo-progress"
    if first_window is None:
        return "missing-pfifo-window-publication"

    progress_before_first = previous_event(parsed.pfifo_progress,
                                           first_opportunity.line_no)
    if progress_before_first is not None:
        return "pfifo-producer-active-before-opportunities"

    progress_after_opportunities = (
        first_progress.line_no > last_opportunity.line_no
        if last_opportunity is not None else False
    )
    last_reason = not_published_reason(last_progress_before_window,
                                       window_start)
    first_reason = published_reason(first_window, window_start)
    if (progress_after_opportunities and
            last_reason == "dma-get-before-window-start" and
            first_reason in {"window-start-reached", "past-window-start"}):
        return "pfifo-producer-starts-after-opportunities-window-start-gated"

    return "pfifo-window-publication-classified"


def emit(parsed: ParsedLog, window_start_override: int | None) -> int:
    first_opportunity = (
        parsed.timer_opportunities[0] if parsed.timer_opportunities else None
    )
    last_opportunity = (
        parsed.timer_opportunities[-1] if parsed.timer_opportunities else None
    )
    first_progress = parsed.pfifo_progress[0] if parsed.pfifo_progress else None
    first_window = parsed.pfifo_windows[0] if parsed.pfifo_windows else None
    window_start = window_start_for(parsed, window_start_override)
    progress_before_first = (
        previous_event(parsed.pfifo_progress, first_opportunity.line_no)
        if first_opportunity is not None else None
    )
    first_progress_after_last = (
        next_event(parsed.pfifo_progress, last_opportunity.line_no)
        if last_opportunity is not None else None
    )
    last_progress_before_window = (
        previous_event(parsed.pfifo_progress, first_window.line_no)
        if first_window is not None else None
    )
    progress_between_opportunities_and_window = (
        events_between(
            parsed.pfifo_progress,
            last_opportunity.line_no,
            first_window.line_no,
        )
        if last_opportunity is not None and first_window is not None else []
    )
    div = divergence(
        parsed,
        first_opportunity,
        last_opportunity,
        first_progress,
        first_window,
        last_progress_before_window,
        window_start,
    )
    result = "fail" if div.startswith("missing-") else "pass"
    first_progress_after_opportunity = (
        "yes" if first_opportunity is not None and first_progress is not None
        and first_progress.line_no > first_opportunity.line_no else "no"
    )
    first_progress_after_last_opportunity = (
        "yes" if last_opportunity is not None and first_progress_after_last is not None
        and first_progress_after_last.line_no > last_opportunity.line_no else "no"
    )

    parts = [
        "PFIFO_WINDOW_PUBLICATION_CLASSIFY",
        f"result={result}",
        f"divergence={div}",
        f"timer_opportunities={len(parsed.timer_opportunities)}",
        f"pfifo_progress={len(parsed.pfifo_progress)}",
        f"pfifo_windows={len(parsed.pfifo_windows)}",
        f"window_start={hex32(window_start)}",
        f"first_opportunity_line={event_line(first_opportunity)}",
        f"last_opportunity_line={event_line(last_opportunity)}",
        f"progress_before_first_opportunity={'yes' if progress_before_first else 'no'}",
        f"last_not_published_before_first_opportunity_line={event_line(progress_before_first)}",
        "last_not_published_reason_before_first_opportunity="
        f"{not_published_reason(progress_before_first, window_start)}",
        f"first_pfifo_progress_line={event_line(first_progress)}",
        f"first_pfifo_progress_delta_from_first_opportunity={line_delta(first_opportunity, first_progress)}",
        f"first_pfifo_progress_delta_from_last_opportunity={line_delta(last_opportunity, first_progress)}",
        f"first_pfifo_progress_after_first_opportunity={first_progress_after_opportunity}",
        "first_pfifo_progress_after_last_opportunity="
        f"{first_progress_after_last_opportunity}",
        f"first_pfifo_progress_op={field(first_progress, 'op')}",
        f"first_pfifo_progress_dma_get={field(first_progress, 'dma_get')}",
        f"first_pfifo_progress_dma_put={field(first_progress, 'dma_put')}",
        f"first_pfifo_progress_available={field(first_progress, 'available')}",
        "progress_between_last_opportunity_and_first_window="
        f"{len(progress_between_opportunities_and_window)}",
        f"last_progress_before_window_line={event_line(last_progress_before_window)}",
        f"last_progress_before_window_delta={line_delta(last_progress_before_window, first_window)}",
        f"last_progress_before_window_op={field(last_progress_before_window, 'op')}",
        f"last_progress_before_window_dma_get={field(last_progress_before_window, 'dma_get')}",
        f"last_progress_before_window_dma_put={field(last_progress_before_window, 'dma_put')}",
        f"last_progress_before_window_available={field(last_progress_before_window, 'available')}",
        "last_not_published_reason_before_window="
        f"{not_published_reason(last_progress_before_window, window_start)}",
        f"first_window_line={event_line(first_window)}",
        f"first_window_delta_from_last_progress={line_delta(last_progress_before_window, first_window)}",
        f"first_window_op={field(first_window, 'op')}",
        f"first_window_dma_get={field(first_window, 'dma_get')}",
        f"first_window_dma_put={field(first_window, 'dma_put')}",
        f"first_window_available={field(first_window, 'available')}",
        f"first_published_reason={published_reason(first_window, window_start)}",
        f"log={parsed.path}",
    ]
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Classify the first PFIFO-window publication relative to the "
            "timer-opportunity window."
        )
    )
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--browser-context", default="browser-runtime")
    parser.add_argument("--window-start", default=None)
    args = parser.parse_args()

    if not args.browser_log.is_file():
        print(
            "PFIFO_WINDOW_PUBLICATION_CLASSIFY result=fail "
            f"reason=missing-browser-log path={args.browser_log}",
            file=sys.stderr,
        )
        return 1

    window_start = parse_int(args.window_start)
    parsed = read_log(args.browser_log, args.browser_context)
    return emit(parsed, window_start)


if __name__ == "__main__":
    raise SystemExit(main())
