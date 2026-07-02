#!/usr/bin/env python3
"""Classify PFIFO pusher-entry timing relative to timer opportunities."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FIELD_RE = re.compile(r'(\S+)=(".*?"|\S+)')
PUSHER_OPS = {
    "pusher-skip",
    "pusher-enter",
    "pusher-stall",
    "pusher-empty",
    "pusher-puller-stall",
    "pusher-puller-done",
    "pusher-new-method-inc",
    "pusher-new-method-non-inc",
}


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


def context_matches(fields: dict[str, str], context: str) -> bool:
    return not context or fields.get("context") == context


def compact_reason(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.:-]+", "-", value.strip()) or "none"


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


def yes_no(value: bool) -> str:
    return "yes" if value else "no"


@dataclass
class Event:
    line_no: int
    kind: str
    fields: dict[str, str]


@dataclass
class ParsedLog:
    path: Path
    xbe_loaded: list[Event]
    entry_ready: list[Event]
    timer_opportunities: list[Event]
    pfifo_progress: list[Event]
    pusher_events: list[Event]
    pusher_enter: list[Event]
    pusher_not_entered: list[Event]


def read_log(path: Path, context: str) -> ParsedLog:
    xbe_loaded: list[Event] = []
    entry_ready: list[Event] = []
    opportunities: list[Event] = []
    progress: list[Event] = []
    pusher_events: list[Event] = []
    pusher_enter: list[Event] = []
    pusher_not_entered: list[Event] = []

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_no, line in enumerate(handle, 1):
            if "BOOT_MARK b6 " not in line:
                continue
            fields = parse_fields(line)
            if not context_matches(fields, context):
                continue
            if fields.get("dashboard") == "xbe-loaded":
                xbe_loaded.append(Event(line_no, "xbe-loaded", fields))
                continue
            if (fields.get("dashboard") == "xbe-entry-probe" and
                    fields.get("status") == "ready"):
                entry_ready.append(Event(line_no, "xbe-entry-ready", fields))
                continue
            if fields.get("headless") == "timer-opportunity":
                opportunities.append(Event(line_no, "timer-opportunity", fields))
                continue
            if fields.get("pfifo") == "progress":
                event = Event(line_no, "pfifo-progress", fields)
                progress.append(event)
                if fields.get("op") in PUSHER_OPS:
                    pusher_events.append(event)
                if fields.get("op") == "pusher-enter":
                    pusher_enter.append(event)
                continue
            if fields.get("pfifo") == "pusher-entry":
                event = Event(line_no, "pfifo-pusher-entry", fields)
                if fields.get("result") in {"no-enter", "skip", "blocked"}:
                    pusher_not_entered.append(event)

    return ParsedLog(
        path=path,
        xbe_loaded=xbe_loaded,
        entry_ready=entry_ready,
        timer_opportunities=opportunities,
        pfifo_progress=progress,
        pusher_events=pusher_events,
        pusher_enter=pusher_enter,
        pusher_not_entered=pusher_not_entered,
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


def pending_dma(event: Event | None) -> str:
    dma_get = parse_int(field(event, "dma_get"))
    dma_put = parse_int(field(event, "dma_put"))
    if dma_get is None or dma_put is None:
        return "unknown"
    return yes_no(dma_get != dma_put)


def dma_to_put(event: Event | None) -> str:
    dma_get = parse_int(field(event, "dma_get"))
    dma_put = parse_int(field(event, "dma_put"))
    if dma_get is None or dma_put is None:
        return "none"
    return str(dma_put - dma_get)


def pusher_enter_reason(event: Event | None) -> str:
    if event is None:
        return "missing-pusher-enter"
    if field(event, "push_access") != "yes":
        return "push-access-disabled"
    if field(event, "dma_push_access") != "yes":
        return "dma-push-access-disabled"
    if field(event, "dma_push_status") != "no":
        return "dma-push-status-busy"
    if field(event, "fifo_access") != "yes":
        return "fifo-access-disabled"
    if field(event, "waiting_flip") == "yes":
        return "waiting-flip"
    if field(event, "waiting_nop") == "yes":
        return "waiting-nop"
    if field(event, "waiting_context") == "yes":
        return "waiting-context"
    if pending_dma(event) == "yes":
        return "entry-gates-open-with-dma-pending"
    if pending_dma(event) == "no":
        return "entry-gates-open-but-dma-empty"
    return "entry-gates-open-dma-state-unknown"


def pusher_not_entered_reason(
    parsed: ParsedLog,
    first_opportunity: Event | None,
    last_opportunity: Event | None,
    first_pusher_event: Event | None,
) -> tuple[str, Event | None, str]:
    if first_opportunity is None:
        return "missing-timer-opportunity", None, "missing"

    explicit = previous_event(parsed.pusher_not_entered, first_opportunity.line_no)
    if explicit is not None:
        return compact_reason(field(explicit, "reason", "explicit-no-enter")), explicit, "explicit"

    previous_pusher = previous_event(parsed.pusher_events, first_opportunity.line_no)
    if previous_pusher is not None:
        return "pusher-event-before-first-opportunity", previous_pusher, "progress"

    first_loaded = parsed.xbe_loaded[0] if parsed.xbe_loaded else None
    if (first_loaded is not None and
            first_loaded.line_no < first_opportunity.line_no and
            first_pusher_event is not None and
            last_opportunity is not None and
            first_pusher_event.line_no > last_opportunity.line_no):
        return "not-called-before-first-opportunity", first_loaded, "static-marker-contract"

    source = field(first_opportunity, "wait_source")
    op = field(first_opportunity, "wait_op")
    known = field(first_opportunity, "wait_pfifo_known")
    fifo_access = field(first_opportunity, "wait_fifo_access")
    return (
        "no-pusher-marker-before-first-opportunity:"
        f"wait-source-{compact_reason(source)}:"
        f"wait-op-{compact_reason(op)}:"
        f"wait-pfifo-known-{compact_reason(known)}:"
        f"wait-fifo-access-{compact_reason(fifo_access)}",
        None,
        "inferred-from-absence",
    )


def divergence(
    first_opportunity: Event | None,
    last_opportunity: Event | None,
    first_pusher_enter: Event | None,
    previous_pusher: Event | None,
) -> str:
    if first_opportunity is None:
        return "missing-timer-opportunity"
    if first_pusher_enter is None:
        return "missing-pusher-enter"
    if previous_pusher is not None:
        return "pusher-active-before-opportunities"
    if first_pusher_enter.line_no > (last_opportunity.line_no if last_opportunity else 0):
        return "pusher-entry-after-opportunities"
    if first_pusher_enter.line_no > first_opportunity.line_no:
        return "pusher-entry-inside-opportunity-window"
    return "pusher-entry-classified"


def emit(parsed: ParsedLog) -> int:
    first_opportunity = (
        parsed.timer_opportunities[0] if parsed.timer_opportunities else None
    )
    last_opportunity = (
        parsed.timer_opportunities[-1] if parsed.timer_opportunities else None
    )
    first_progress = parsed.pfifo_progress[0] if parsed.pfifo_progress else None
    first_pusher_event = parsed.pusher_events[0] if parsed.pusher_events else None
    first_pusher_enter = parsed.pusher_enter[0] if parsed.pusher_enter else None
    first_loaded = parsed.xbe_loaded[0] if parsed.xbe_loaded else None
    first_entry_ready = parsed.entry_ready[0] if parsed.entry_ready else None
    previous_pusher = (
        previous_event(parsed.pusher_events, first_opportunity.line_no)
        if first_opportunity is not None else None
    )
    first_pusher_after_last = (
        next_event(parsed.pusher_events, last_opportunity.line_no)
        if last_opportunity is not None else None
    )
    progress_between = (
        events_between(
            parsed.pfifo_progress,
            last_opportunity.line_no,
            first_pusher_enter.line_no,
        )
        if last_opportunity is not None and first_pusher_enter is not None else []
    )
    not_entered_reason, not_entered_event, not_entered_source = (
        pusher_not_entered_reason(
            parsed, first_opportunity, last_opportunity, first_pusher_event)
    )
    enter_reason = pusher_enter_reason(first_pusher_enter)
    div = divergence(
        first_opportunity,
        last_opportunity,
        first_pusher_enter,
        previous_pusher,
    )
    result = "fail" if div.startswith("missing-") else "pass"

    parts = [
        "PFIFO_PUSHER_ENTRY_CLASSIFY",
        f"result={result}",
        f"divergence={div}",
        f"timer_opportunities={len(parsed.timer_opportunities)}",
        f"pfifo_progress={len(parsed.pfifo_progress)}",
        f"pusher_events={len(parsed.pusher_events)}",
        f"pusher_enter_events={len(parsed.pusher_enter)}",
        f"explicit_not_entered_markers={len(parsed.pusher_not_entered)}",
        f"xbe_loaded_line={event_line(first_loaded)}",
        f"entry_ready_line={event_line(first_entry_ready)}",
        "marker_contract=pusher-skip-or-enter-after-xbe-loaded",
        f"first_opportunity_line={event_line(first_opportunity)}",
        f"last_opportunity_line={event_line(last_opportunity)}",
        f"first_opportunity_wait_source={field(first_opportunity, 'wait_source')}",
        f"first_opportunity_wait_op={field(first_opportunity, 'wait_op')}",
        f"first_opportunity_wait_pfifo_known={field(first_opportunity, 'wait_pfifo_known')}",
        f"first_opportunity_wait_fifo_access={field(first_opportunity, 'wait_fifo_access')}",
        f"first_opportunity_wait_dma_get={field(first_opportunity, 'wait_dma_get')}",
        f"first_opportunity_wait_dma_put={field(first_opportunity, 'wait_dma_put')}",
        f"previous_pusher_before_first_opportunity={'yes' if previous_pusher else 'no'}",
        f"previous_pusher_line={event_line(previous_pusher)}",
        f"previous_pusher_op={field(previous_pusher, 'op')}",
        f"last_pusher_not_entered_line={event_line(not_entered_event)}",
        f"last_pusher_not_entered_source={not_entered_source}",
        f"last_pusher_not_entered_reason_before_first_opportunity={not_entered_reason}",
        f"first_pfifo_progress_line={event_line(first_progress)}",
        f"first_pfifo_progress_op={field(first_progress, 'op')}",
        f"first_pusher_event_line={event_line(first_pusher_event)}",
        f"first_pusher_event_op={field(first_pusher_event, 'op')}",
        f"first_pusher_after_last_opportunity_line={event_line(first_pusher_after_last)}",
        f"first_pusher_after_last_opportunity_op={field(first_pusher_after_last, 'op')}",
        f"progress_between_last_opportunity_and_first_pusher_enter={len(progress_between)}",
        f"first_pusher_enter_line={event_line(first_pusher_enter)}",
        f"first_pusher_enter_delta_from_first_opportunity={line_delta(first_opportunity, first_pusher_enter)}",
        f"first_pusher_enter_delta_from_last_opportunity={line_delta(last_opportunity, first_pusher_enter)}",
        f"first_pusher_enter_reason={enter_reason}",
        f"first_pusher_enter_dma_get={field(first_pusher_enter, 'dma_get')}",
        f"first_pusher_enter_dma_put={field(first_pusher_enter, 'dma_put')}",
        f"first_pusher_enter_dma_to_put={dma_to_put(first_pusher_enter)}",
        f"first_pusher_enter_pending_dma={pending_dma(first_pusher_enter)}",
        f"first_pusher_enter_push_access={field(first_pusher_enter, 'push_access')}",
        f"first_pusher_enter_pull_access={field(first_pusher_enter, 'pull_access')}",
        f"first_pusher_enter_dma_push_access={field(first_pusher_enter, 'dma_push_access')}",
        f"first_pusher_enter_dma_push_status={field(first_pusher_enter, 'dma_push_status')}",
        f"first_pusher_enter_fifo_access={field(first_pusher_enter, 'fifo_access')}",
        f"first_pusher_enter_waiting_flip={field(first_pusher_enter, 'waiting_flip')}",
        f"first_pusher_enter_waiting_nop={field(first_pusher_enter, 'waiting_nop')}",
        f"first_pusher_enter_waiting_context={field(first_pusher_enter, 'waiting_context')}",
        f"first_pusher_enter_halt={field(first_pusher_enter, 'halt')}",
        f"first_pusher_enter_fifo_kick={field(first_pusher_enter, 'fifo_kick')}",
        f"log={parsed.path}",
    ]
    print(" ".join(parts))
    return 1 if result == "fail" else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Classify the first PFIFO pusher-enter marker relative to the "
            "timer-opportunity window."
        )
    )
    parser.add_argument("--browser-log", required=True, type=Path)
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args()

    if not args.browser_log.is_file():
        print(
            "PFIFO_PUSHER_ENTRY_CLASSIFY result=fail "
            f"reason=missing-browser-log path={args.browser_log}",
            file=sys.stderr,
        )
        return 1

    parsed = read_log(args.browser_log, args.browser_context)
    return emit(parsed)


if __name__ == "__main__":
    raise SystemExit(main())
