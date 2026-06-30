#!/usr/bin/env python3
"""Compare native/browser B6 interrupt flow after PFIFO reaches idle."""

import argparse
import re
import sys
from dataclasses import dataclass, field


MARKER_RE = re.compile(r'(\S+)=(".*?"|\S+)')


def parse_value(value):
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    return value


def parse_marker(line):
    return {key: parse_value(value) for key, value in MARKER_RE.findall(line)}


def bool_word(value):
    return "yes" if value else "no"


def compact_list(values, limit):
    if not values:
        return "none"
    limited = values[:limit]
    result = ",".join(limited)
    if len(values) > limit:
        result += ",..."
    return result


def marker_field_values(events, field):
    return [event.marker.get(field, "none") for event in events]


def unique_extra(values, reference):
    reference_set = set(reference)
    extras = []
    for value in values:
        if value not in reference_set and value not in extras:
            extras.append(value)
    return extras


def first_event_for_vector(events, vectors):
    vector_set = set(vectors)
    for event in events:
        if event.marker.get("intno", "none") in vector_set:
            return event
    return None


def first_event_for_marker_field(events, field, values):
    value_set = set(values)
    for event in events:
        if event.marker.get(field, "none") in value_set:
            return event
    return None


def is_stream_idle_pfifo_window(marker):
    if marker.get("pfifo") != "window":
        return False
    if marker.get("op") != "pusher-empty":
        return False
    dma_get = marker.get("dma_get", "none")
    dma_put = marker.get("dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


def is_pfifo_empty_wait(marker):
    return (
        marker.get("nv2a_wait_source") == "pfifo-window"
        and marker.get("nv2a_wait_op") == "pusher-empty"
    )


def event_key(event):
    return event.key


@dataclass
class FlowEvent:
    kind: str
    key: str
    line_no: int
    marker: dict = field(default_factory=dict)


@dataclass
class ParsedFlow:
    label: str
    path: str
    idle_count: int = 0
    first_idle_line: int = 0
    latest_idle_line: int = 0
    loop_events: list = field(default_factory=list)
    service_events: list = field(default_factory=list)
    iret_events: list = field(default_factory=list)
    hard_irq_events: list = field(default_factory=list)
    pic_ack_events: list = field(default_factory=list)
    pic_line_events: list = field(default_factory=list)
    lpc_route_events: list = field(default_factory=list)
    pm_timer_events: list = field(default_factory=list)
    pm_evt_write_events: list = field(default_factory=list)
    pm_sci_events: list = field(default_factory=list)
    ac97_callback_events: list = field(default_factory=list)
    ac97_bm_write_events: list = field(default_factory=list)
    ac97_transfer_events: list = field(default_factory=list)
    ac97_irq_events: list = field(default_factory=list)
    timer_events: list = field(default_factory=list)
    tcg_timer_events: list = field(default_factory=list)
    main_loop_timer_events: list = field(default_factory=list)
    flow_events: list = field(default_factory=list)

    def stream_idle_seen(self):
        return self.idle_count > 0

    def first_service(self):
        return self.service_events[0] if self.service_events else None

    def first_iret(self):
        return self.iret_events[0] if self.iret_events else None

    def preferred_service(self):
        idle = [event for event in self.service_events if is_pfifo_empty_wait(event.marker)]
        if idle:
            return idle[-1]
        return self.first_service()

    def iret_for_service(self, service):
        if not service:
            return None

        service_hash = service.marker.get("stack_hash")
        for event in self.iret_events:
            if (
                event.line_no > service.line_no
                and event.marker.get("stack_hash") == service_hash
                and is_pfifo_empty_wait(event.marker)
            ):
                return event

        for event in self.iret_events:
            if (
                event.line_no > service.line_no
                and event.marker.get("stack_hash") == service_hash
            ):
                return event

        for event in self.iret_events:
            if event.line_no > service.line_no:
                return event

        return None

    def preferred_iret(self):
        return self.iret_for_service(self.preferred_service()) or self.first_iret()

    def first_loop_after_first_service(self):
        service = self.first_service()
        if not service:
            return None
        for event in self.loop_events:
            if event.line_no > service.line_no:
                return event
        return None

    def first_loop_after_first_iret(self):
        iret = self.first_iret()
        return self.first_loop_after_iret(iret)

    def first_loop_after_iret(self, iret):
        if not iret:
            return None
        for event in self.loop_events:
            if event.line_no > iret.line_no:
                return event
        return None

    def first_return_loop_after_first_iret(self):
        iret = self.first_iret()
        return self.first_return_loop_after_iret(iret)

    def first_return_loop_after_iret(self, iret):
        if not iret:
            return None
        return_pc = iret.marker.get("eip", "none")
        for event in self.loop_events:
            if (
                event.line_no > iret.line_no
                and event.marker.get("start_pc", "none") == return_pc
            ):
                return event
        return None

    def vectors(self):
        return [event.marker.get("intno", "none") for event in self.service_events]

    def pic_ack_vectors(self):
        return [event.marker.get("intno", "none") for event in self.pic_ack_events]

    def pic_line_assert_irqs(self):
        return [
            event.marker.get("guest_irq", "none")
            for event in self.pic_line_events
            if event.marker.get("level") == "assert"
        ]

    def lpc_route_assert_irqs(self):
        return [
            event.marker.get("pic_irq", "none")
            for event in self.lpc_route_events
            if event.marker.get("level") == "assert"
            and event.marker.get("delivered") == "yes"
        ]

    def pm_sci_assert_reasons(self):
        return [
            event.marker.get("reason", "none")
            for event in self.pm_sci_events
            if event.marker.get("sci_level") == "assert"
        ]

    def ac97_irq_assert_indices(self):
        return [
            event.marker.get("bm_index", "none")
            for event in self.ac97_irq_events
            if event.marker.get("level") == "assert"
        ]


def marker_context_matches(marker, context):
    return not context or marker.get("context") == context


def should_collect(marker, stream_idle_seen):
    return stream_idle_seen or marker.get("stream_idle") == "yes"


def append_limited(items, item, limit):
    if len(items) < limit:
        items.append(item)


def parse_log(path, label, context, limit):
    parsed = ParsedFlow(label=label, path=path)
    pending_service_before = None
    pending_iret_before = None

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                if "BOOT_MARK b6 " not in raw_line:
                    continue
                marker = parse_marker(raw_line)
                if not marker_context_matches(marker, context):
                    continue

                if is_stream_idle_pfifo_window(marker):
                    parsed.idle_count += 1
                    if not parsed.first_idle_line:
                        parsed.first_idle_line = line_no
                    parsed.latest_idle_line = line_no
                    continue

                if not should_collect(marker, parsed.stream_idle_seen()):
                    continue

                if marker.get("tcg") == "timer-pump":
                    key = (
                        "timer:tcg:"
                        f"{marker.get('mode', 'none')}:"
                        f"pc={marker.get('eip', 'none')}:"
                        f"irq={marker.get('cpu_interrupt_request', 'none')}:"
                        f"progress={marker.get('timer_progress', 'unknown')}"
                    )
                    event = FlowEvent("timer", key, line_no, marker)
                    append_limited(parsed.timer_events, event, limit)
                    append_limited(parsed.tcg_timer_events, event, limit)
                    continue

                if marker.get("main-loop") == "timers":
                    key = (
                        "timer:main-loop:"
                        f"{marker.get('source', 'none')}:"
                        f"pc={marker.get('eip', 'none')}:"
                        f"irq={marker.get('cpu_interrupt_request', 'none')}:"
                        f"progress={marker.get('timer_progress', 'unknown')}"
                    )
                    event = FlowEvent("timer", key, line_no, marker)
                    append_limited(parsed.timer_events, event, limit)
                    append_limited(parsed.main_loop_timer_events, event, limit)
                    continue

                if marker.get("cpu") == "hard-irq":
                    key = (
                        "irq:"
                        f"{marker.get('op', 'none')}:"
                        f"pc={marker.get('eip', 'none')}:"
                        f"before={marker.get('request_before', 'none')}:"
                        f"after={marker.get('request_after', 'none')}"
                    )
                    event = FlowEvent("hard-irq", key, line_no, marker)
                    append_limited(parsed.hard_irq_events, event, limit)
                    append_limited(parsed.flow_events, event, limit)
                    continue

                if marker.get("pic") == "irq-ack":
                    key = (
                        "ack:"
                        f"{marker.get('intno', 'none')}:"
                        f"guest={marker.get('guest_irq', 'none')}:"
                        f"master={marker.get('master_irq', 'none')}:"
                        f"slave={marker.get('slave_irq', 'none')}:"
                        f"mirr={marker.get('master_irr_before', 'none')}"
                        f"->{marker.get('master_irr_after', 'none')}:"
                        f"misr={marker.get('master_isr_before', 'none')}"
                        f"->{marker.get('master_isr_after', 'none')}:"
                        f"sirr={marker.get('slave_irr_before', 'none')}"
                        f"->{marker.get('slave_irr_after', 'none')}:"
                        f"sisr={marker.get('slave_isr_before', 'none')}"
                        f"->{marker.get('slave_isr_after', 'none')}"
                    )
                    event = FlowEvent("pic-ack", key, line_no, marker)
                    append_limited(parsed.pic_ack_events, event, limit)
                    append_limited(parsed.flow_events, event, limit)
                    continue

                if marker.get("pic") == "irq-line":
                    key = (
                        "line:"
                        f"{marker.get('guest_irq', 'none')}:"
                        f"{marker.get('level', 'none')}:"
                        f"chip={marker.get('chip', 'none')}:"
                        f"irq={marker.get('irq', 'none')}:"
                        f"irr={marker.get('irr_before', 'none')}"
                        f"->{marker.get('irr_after', 'none')}:"
                        f"last={marker.get('last_irr_before', 'none')}"
                        f"->{marker.get('last_irr_after', 'none')}:"
                        f"out={marker.get('output_irq', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("pic-line", key, line_no, marker)
                    append_limited(parsed.pic_line_events, event, limit)
                    continue

                if marker.get("lpc") == "irq-route":
                    key = (
                        "route:"
                        f"{marker.get('pic_irq', 'none')}:"
                        f"{marker.get('level', 'none')}:"
                        f"source={marker.get('source', 'none')}:"
                        f"route={marker.get('route_type', 'none')}:"
                        f"input={marker.get('input_irq', 'none')}:"
                        f"delivered={marker.get('delivered', 'none')}:"
                        f"int={marker.get('int_route', 'none')}:"
                        f"pirq={marker.get('pirq_route', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("lpc-route", key, line_no, marker)
                    append_limited(parsed.lpc_route_events, event, limit)
                    continue

                if marker.get("xbox-pm") == "evt-write":
                    key = (
                        "pm-write:"
                        f"{marker.get('op', 'none')}:"
                        f"addr={marker.get('addr', 'none')}:"
                        f"val={marker.get('value', 'none')}:"
                        f"sts={marker.get('pm1_sts_before', 'none')}"
                        f"->{marker.get('pm1_sts_after', 'none')}:"
                        f"en={marker.get('pm1_en_before', 'none')}"
                        f"->{marker.get('pm1_en_after', 'none')}:"
                        f"timer={marker.get('timer_enabled_after', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("pm-evt-write", key, line_no, marker)
                    append_limited(parsed.pm_evt_write_events, event, limit)
                    continue

                if marker.get("xbox-pm") == "tmr-callback":
                    key = (
                        "pm-timer:"
                        f"{marker.get('phase', 'none')}:"
                        f"ticks={marker.get('timer_ticks', 'none')}:"
                        f"overflow={marker.get('overflow_time', 'none')}:"
                        f"sts={marker.get('pm1_sts_before', 'none')}"
                        f"->{marker.get('pm1_sts_after', 'none')}:"
                        f"en={marker.get('pm1_en', 'none')}:"
                        f"masked={marker.get('pm1_masked_after', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("pm-timer", key, line_no, marker)
                    append_limited(parsed.pm_timer_events, event, limit)
                    continue

                if marker.get("xbox-pm") == "sci-update":
                    key = (
                        "pm:"
                        f"{marker.get('reason', 'none')}:"
                        f"{marker.get('sci_level', 'none')}:"
                        f"pm1={marker.get('pm1_sts', 'none')}"
                        f"/{marker.get('pm1_en', 'none')}"
                        f"/{marker.get('pm1_masked', 'none')}:"
                        f"gpe0={marker.get('gpe0_sts', 'none')}"
                        f"/{marker.get('gpe0_en', 'none')}"
                        f"/{marker.get('gpe0_masked', 'none')}:"
                        f"timer={marker.get('timer_enabled', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("pm-sci", key, line_no, marker)
                    append_limited(parsed.pm_sci_events, event, limit)
                    continue

                if marker.get("ac97") == "callback":
                    key = (
                        "ac97-callback:"
                        f"{marker.get('callback', 'none')}:"
                        f"bm={marker.get('bm_index', 'none')}:"
                        f"free={marker.get('free_or_avail', 'none')}:"
                        f"sr={marker.get('sr', 'none')}:"
                        f"cr={marker.get('cr', 'none')}:"
                        f"civ={marker.get('civ', 'none')}:"
                        f"lvi={marker.get('lvi', 'none')}:"
                        f"picb={marker.get('picb', 'none')}:"
                        f"bd={marker.get('bd_addr', 'none')}"
                        f"/{marker.get('bd_ctl_len', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("ac97-callback", key, line_no, marker)
                    append_limited(parsed.ac97_callback_events, event, limit)
                    continue

                if marker.get("ac97") == "bm-write":
                    key = (
                        "ac97-write:"
                        f"bm={marker.get('bm_index', 'none')}:"
                        f"reg={marker.get('reg', 'none')}:"
                        f"val={marker.get('value', 'none')}:"
                        f"bdbar={marker.get('bdbar_before', 'none')}"
                        f"->{marker.get('bdbar_after', 'none')}:"
                        f"lvi={marker.get('lvi_before', 'none')}"
                        f"->{marker.get('lvi_after', 'none')}:"
                        f"cr={marker.get('cr_before', 'none')}"
                        f"->{marker.get('cr_after', 'none')}:"
                        f"sr={marker.get('sr_before', 'none')}"
                        f"->{marker.get('sr_after', 'none')}:"
                        f"picb={marker.get('picb_before', 'none')}"
                        f"->{marker.get('picb_after', 'none')}:"
                        f"bd={marker.get('bd_addr_after', 'none')}"
                        f"/{marker.get('bd_ctl_len_after', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("ac97-bm-write", key, line_no, marker)
                    append_limited(parsed.ac97_bm_write_events, event, limit)
                    continue

                if marker.get("ac97") == "transfer":
                    key = (
                        "ac97-transfer:"
                        f"bm={marker.get('bm_index', 'none')}:"
                        f"phase={marker.get('phase', 'none')}:"
                        f"sr={marker.get('sr_before', 'none')}"
                        f"->{marker.get('sr_after', 'none')}:"
                        f"cr={marker.get('cr', 'none')}:"
                        f"civ={marker.get('civ', 'none')}:"
                        f"lvi={marker.get('lvi', 'none')}:"
                        f"picb={marker.get('picb', 'none')}:"
                        f"bd={marker.get('bd_addr', 'none')}"
                        f"/{marker.get('bd_ctl_len', 'none')}:"
                        f"ioc={marker.get('bd_ioc', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("ac97-transfer", key, line_no, marker)
                    append_limited(parsed.ac97_transfer_events, event, limit)
                    continue

                if marker.get("ac97") == "irq-update":
                    key = (
                        "ac97:"
                        f"bm={marker.get('bm_index', 'none')}:"
                        f"{marker.get('level', 'none')}:"
                        f"sr={marker.get('sr_before', 'none')}"
                        f"->{marker.get('sr_after', 'none')}:"
                        f"mask={marker.get('old_mask', 'none')}"
                        f"->{marker.get('new_mask', 'none')}:"
                        f"cr={marker.get('cr', 'none')}:"
                        f"glob={marker.get('glob_sta_before', 'none')}"
                        f"->{marker.get('glob_sta_after', 'none')}:"
                        f"civ={marker.get('civ', 'none')}:"
                        f"lvi={marker.get('lvi', 'none')}:"
                        f"picb={marker.get('picb', 'none')}:"
                        f"bd={marker.get('bd_addr', 'none')}"
                        f"/{marker.get('bd_ctl_len', 'none')}:"
                        f"eip={marker.get('eip', 'none')}"
                    )
                    event = FlowEvent("ac97-irq", key, line_no, marker)
                    append_limited(parsed.ac97_irq_events, event, limit)
                    continue

                if marker.get("cpu") == "hard-irq-service":
                    phase = marker.get("phase")
                    if phase == "before":
                        pending_service_before = (line_no, marker)
                    elif phase == "after":
                        before_line_no, before = (
                            pending_service_before
                            if pending_service_before
                            else (line_no, {})
                        )
                        intno = marker.get("intno", before.get("intno", "none"))
                        key = (
                            "svc:"
                            f"{intno}:"
                            f"{before.get('eip', 'none')}->{marker.get('eip', 'none')}:"
                            f"ret={marker.get('stack0', 'none')}:"
                            f"hash={marker.get('stack_hash', 'none')}"
                        )
                        merged = dict(before)
                        merged.update(marker)
                        merged["before_line"] = before_line_no
                        event = FlowEvent("service", key, line_no, merged)
                        append_limited(parsed.service_events, event, limit)
                        append_limited(parsed.flow_events, event, limit)
                        pending_service_before = None
                    continue

                if marker.get("cpu") == "iret":
                    phase = marker.get("phase")
                    if phase == "before":
                        pending_iret_before = (line_no, marker)
                    elif phase == "after":
                        before_line_no, before = (
                            pending_iret_before if pending_iret_before else (line_no, {})
                        )
                        key = (
                            "iret:"
                            f"{before.get('eip', 'none')}->{marker.get('eip', 'none')}:"
                            f"ret={before.get('stack0', 'none')}:"
                            f"hash={before.get('stack_hash', 'none')}"
                        )
                        merged = dict(before)
                        merged.update(marker)
                        merged["before_line"] = before_line_no
                        event = FlowEvent("iret", key, line_no, merged)
                        append_limited(parsed.iret_events, event, limit)
                        append_limited(parsed.flow_events, event, limit)
                        pending_iret_before = None
                    continue

                if marker.get("dashboard") == "kernel-loop-probe":
                    key = (
                        "loop:"
                        f"{marker.get('start_pc', 'none')}->{marker.get('next_pc', 'none')}:"
                        f"{marker.get('loop_kind', 'none')}:"
                        f"if={marker.get('interrupts_enabled', 'unknown')}:"
                        f"inh={marker.get('irq_inhibited', 'unknown')}:"
                        f"irq={marker.get('cpu_interrupt_request', 'none')}:"
                        f"pending={marker.get('pending_interrupt', 'unknown')}"
                    )
                    event = FlowEvent("loop", key, line_no, marker)
                    append_limited(parsed.loop_events, event, limit)
                    append_limited(parsed.flow_events, event, limit)
                    continue
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return parsed


def first_mismatch(native_events, browser_events):
    count = min(len(native_events), len(browser_events))
    for index in range(count):
        if event_key(native_events[index]) != event_key(browser_events[index]):
            return index, native_events[index], browser_events[index]
    if len(native_events) != len(browser_events):
        if len(native_events) < len(browser_events):
            return count, None, browser_events[count]
        return count, native_events[count], None
    return -1, None, None


def pump_active_count(events):
    return sum(
        1 for event in events if event.marker.get("timer_pump_active") == "yes"
    )


def timer_progress_count(events):
    return sum(1 for event in events if event.marker.get("timer_progress") == "yes")


def first_timer_progress_event(events):
    for event in events:
        if event.marker.get("timer_progress") == "yes":
            return event
    return None


def timer_divergence_for(native, browser):
    native_main_loop_progress = timer_progress_count(native.main_loop_timer_events)
    browser_main_loop_progress = timer_progress_count(browser.main_loop_timer_events)
    native_tcg_progress = timer_progress_count(native.tcg_timer_events)
    browser_tcg_progress = timer_progress_count(browser.tcg_timer_events)

    if native_main_loop_progress > 0 and browser_main_loop_progress == 0:
        return "browser-missing-main-loop-timer-progress"
    if native_tcg_progress == 0 and browser_tcg_progress > 0:
        return "browser-only-tcg-timer-progress"
    if native_main_loop_progress != browser_main_loop_progress:
        return "main-loop-timer-progress-count-mismatch"
    if native_tcg_progress != browser_tcg_progress:
        return "tcg-timer-progress-count-mismatch"
    return "none"


def divergence_for(native, browser):
    if not native.stream_idle_seen() or not browser.stream_idle_seen():
        return "command-stream-not-idle"
    if not native.service_events or not browser.service_events:
        return "missing-interrupt-service"

    native_vectors = native.vectors()
    browser_vectors = browser.vectors()
    browser_extra = unique_extra(browser_vectors, native_vectors)
    native_extra = unique_extra(native_vectors, browser_vectors)
    if browser_extra:
        return "browser-extra-interrupt-vector"
    if native_extra:
        return "native-extra-interrupt-vector"

    vector_count = min(len(native_vectors), len(browser_vectors))
    for index in range(vector_count):
        if native_vectors[index] != browser_vectors[index]:
            return "interrupt-vector-sequence-mismatch"

    native_preferred_service = native.preferred_service()
    browser_preferred_service = browser.preferred_service()
    if event_key(native_preferred_service) != event_key(browser_preferred_service):
        return "interrupt-service-frame-mismatch"

    native_preferred_iret = native.iret_for_service(native_preferred_service)
    browser_preferred_iret = browser.iret_for_service(browser_preferred_service)
    if native_preferred_iret and browser_preferred_iret:
        if event_key(native_preferred_iret) != event_key(browser_preferred_iret):
            return "iret-return-mismatch"

    native_loop = native.first_loop_after_first_service()
    browser_loop = browser.first_loop_after_first_service()
    if native_loop and browser_loop and event_key(native_loop) != event_key(browser_loop):
        return "post-service-loop-edge-mismatch"

    native_return_loop = native.first_return_loop_after_iret(native_preferred_iret)
    browser_return_loop = browser.first_return_loop_after_iret(browser_preferred_iret)
    if native_return_loop and browser_return_loop:
        if event_key(native_return_loop) != event_key(browser_return_loop):
            return "post-iret-return-loop-edge-mismatch"
    elif native_preferred_iret and browser_preferred_iret:
        if bool(native_return_loop) != bool(browser_return_loop):
            return "post-iret-return-loop-evidence-mismatch"

    mismatch_index, _, _ = first_mismatch(native.flow_events, browser.flow_events)
    if mismatch_index >= 0:
        return "flow-event-sequence-mismatch"

    return "none"


def side_fields(prefix, parsed, list_limit):
    first_service = parsed.first_service()
    first_iret = parsed.first_iret()
    preferred_service = parsed.preferred_service()
    preferred_iret = parsed.preferred_iret()
    first_loop_after_service = parsed.first_loop_after_first_service()
    first_loop_after_iret = parsed.first_loop_after_first_iret()
    first_return_loop_after_iret = parsed.first_return_loop_after_first_iret()
    first_loop_after_preferred_iret = parsed.first_loop_after_iret(preferred_iret)
    first_return_loop_after_preferred_iret = parsed.first_return_loop_after_iret(
        preferred_iret
    )
    first_pm_sci_assert = next(
        (
            event
            for event in parsed.pm_sci_events
            if event.marker.get("sci_level") == "assert"
        ),
        None,
    )
    first_ac97_irq_assert = next(
        (
            event
            for event in parsed.ac97_irq_events
            if event.marker.get("level") == "assert"
        ),
        None,
    )
    first_tcg_timer_progress = first_timer_progress_event(parsed.tcg_timer_events)
    first_main_loop_timer_progress = first_timer_progress_event(
        parsed.main_loop_timer_events
    )
    fields = {
        f"{prefix}_idle_seen": bool_word(parsed.stream_idle_seen()),
        f"{prefix}_idle_count": parsed.idle_count,
        f"{prefix}_first_idle_line": parsed.first_idle_line or "none",
        f"{prefix}_latest_idle_line": parsed.latest_idle_line or "none",
        f"{prefix}_service_events": len(parsed.service_events),
        f"{prefix}_vectors": compact_list(parsed.vectors(), list_limit),
        f"{prefix}_first_service": event_key(first_service) if first_service else "none",
        f"{prefix}_first_iret": event_key(first_iret) if first_iret else "none",
        f"{prefix}_preferred_service": (
            event_key(preferred_service) if preferred_service else "none"
        ),
        f"{prefix}_preferred_iret": (
            event_key(preferred_iret) if preferred_iret else "none"
        ),
        f"{prefix}_loop_events": len(parsed.loop_events),
        f"{prefix}_first_post_service_loop": (
            event_key(first_loop_after_service) if first_loop_after_service else "none"
        ),
        f"{prefix}_first_post_iret_loop": (
            event_key(first_loop_after_iret) if first_loop_after_iret else "none"
        ),
        f"{prefix}_first_iret_return_loop": (
            event_key(first_return_loop_after_iret)
            if first_return_loop_after_iret
            else "none"
        ),
        f"{prefix}_first_post_preferred_iret_loop": (
            event_key(first_loop_after_preferred_iret)
            if first_loop_after_preferred_iret
            else "none"
        ),
        f"{prefix}_first_preferred_iret_return_loop": (
            event_key(first_return_loop_after_preferred_iret)
            if first_return_loop_after_preferred_iret
            else "none"
        ),
        f"{prefix}_hard_irq_events": len(parsed.hard_irq_events),
        f"{prefix}_first_hard_irq": (
            event_key(parsed.hard_irq_events[0]) if parsed.hard_irq_events else "none"
        ),
        f"{prefix}_pic_ack_events": len(parsed.pic_ack_events),
        f"{prefix}_pic_ack_vectors": compact_list(
            parsed.pic_ack_vectors(), list_limit
        ),
        f"{prefix}_first_pic_ack": (
            event_key(parsed.pic_ack_events[0]) if parsed.pic_ack_events else "none"
        ),
        f"{prefix}_pic_line_events": len(parsed.pic_line_events),
        f"{prefix}_pic_line_assert_irqs": compact_list(
            parsed.pic_line_assert_irqs(), list_limit
        ),
        f"{prefix}_first_pic_line": (
            event_key(parsed.pic_line_events[0]) if parsed.pic_line_events else "none"
        ),
        f"{prefix}_lpc_route_events": len(parsed.lpc_route_events),
        f"{prefix}_lpc_route_assert_irqs": compact_list(
            parsed.lpc_route_assert_irqs(), list_limit
        ),
        f"{prefix}_first_lpc_route": (
            event_key(parsed.lpc_route_events[0]) if parsed.lpc_route_events else "none"
        ),
        f"{prefix}_pm_timer_events": len(parsed.pm_timer_events),
        f"{prefix}_pm_timer_pump_active_events": pump_active_count(
            parsed.pm_timer_events
        ),
        f"{prefix}_first_pm_timer": (
            event_key(parsed.pm_timer_events[0])
            if parsed.pm_timer_events
            else "none"
        ),
        f"{prefix}_pm_evt_write_events": len(parsed.pm_evt_write_events),
        f"{prefix}_pm_evt_write_pump_active_events": pump_active_count(
            parsed.pm_evt_write_events
        ),
        f"{prefix}_first_pm_evt_write": (
            event_key(parsed.pm_evt_write_events[0])
            if parsed.pm_evt_write_events
            else "none"
        ),
        f"{prefix}_pm_sci_events": len(parsed.pm_sci_events),
        f"{prefix}_pm_sci_pump_active_events": pump_active_count(
            parsed.pm_sci_events
        ),
        f"{prefix}_pm_sci_assert_reasons": compact_list(
            parsed.pm_sci_assert_reasons(), list_limit
        ),
        f"{prefix}_first_pm_sci": (
            event_key(parsed.pm_sci_events[0]) if parsed.pm_sci_events else "none"
        ),
        f"{prefix}_first_pm_sci_assert": (
            event_key(first_pm_sci_assert) if first_pm_sci_assert else "none"
        ),
        f"{prefix}_ac97_callback_events": len(parsed.ac97_callback_events),
        f"{prefix}_ac97_callback_pump_active_events": pump_active_count(
            parsed.ac97_callback_events
        ),
        f"{prefix}_first_ac97_callback": (
            event_key(parsed.ac97_callback_events[0])
            if parsed.ac97_callback_events
            else "none"
        ),
        f"{prefix}_ac97_bm_write_events": len(parsed.ac97_bm_write_events),
        f"{prefix}_ac97_bm_write_pump_active_events": pump_active_count(
            parsed.ac97_bm_write_events
        ),
        f"{prefix}_first_ac97_bm_write": (
            event_key(parsed.ac97_bm_write_events[0])
            if parsed.ac97_bm_write_events
            else "none"
        ),
        f"{prefix}_ac97_transfer_events": len(parsed.ac97_transfer_events),
        f"{prefix}_ac97_transfer_pump_active_events": pump_active_count(
            parsed.ac97_transfer_events
        ),
        f"{prefix}_first_ac97_transfer": (
            event_key(parsed.ac97_transfer_events[0])
            if parsed.ac97_transfer_events
            else "none"
        ),
        f"{prefix}_ac97_irq_events": len(parsed.ac97_irq_events),
        f"{prefix}_ac97_irq_pump_active_events": pump_active_count(
            parsed.ac97_irq_events
        ),
        f"{prefix}_ac97_irq_assert_indices": compact_list(
            parsed.ac97_irq_assert_indices(), list_limit
        ),
        f"{prefix}_first_ac97_irq": (
            event_key(parsed.ac97_irq_events[0]) if parsed.ac97_irq_events else "none"
        ),
        f"{prefix}_first_ac97_irq_assert": (
            event_key(first_ac97_irq_assert) if first_ac97_irq_assert else "none"
        ),
        f"{prefix}_timer_events": len(parsed.timer_events),
        f"{prefix}_first_timer": (
            event_key(parsed.timer_events[0]) if parsed.timer_events else "none"
        ),
        f"{prefix}_tcg_timer_events": len(parsed.tcg_timer_events),
        f"{prefix}_tcg_timer_progress_events": timer_progress_count(
            parsed.tcg_timer_events
        ),
        f"{prefix}_first_tcg_timer": (
            event_key(parsed.tcg_timer_events[0])
            if parsed.tcg_timer_events
            else "none"
        ),
        f"{prefix}_first_tcg_timer_progress": (
            event_key(first_tcg_timer_progress)
            if first_tcg_timer_progress
            else "none"
        ),
        f"{prefix}_main_loop_timer_events": len(parsed.main_loop_timer_events),
        f"{prefix}_main_loop_timer_sources": compact_list(
            marker_field_values(parsed.main_loop_timer_events, "source"),
            list_limit,
        ),
        f"{prefix}_main_loop_timer_progress_events": timer_progress_count(
            parsed.main_loop_timer_events
        ),
        f"{prefix}_first_main_loop_timer": (
            event_key(parsed.main_loop_timer_events[0])
            if parsed.main_loop_timer_events
            else "none"
        ),
        f"{prefix}_first_main_loop_timer_progress": (
            event_key(first_main_loop_timer_progress)
            if first_main_loop_timer_progress
            else "none"
        ),
        f"{prefix}_flow_events": len(parsed.flow_events),
    }
    return fields


def emit_fail(reason, **fields):
    parts = [f"POST_IDLE_INTERRUPT_FLOW_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    parser.add_argument("--event-limit", type=int, default=4096)
    parser.add_argument("--list-limit", type=int, default=12)
    args = parser.parse_args()

    try:
        native = parse_log(
            args.native_log, "native", args.native_context, args.event_limit
        )
        browser = parse_log(
            args.browser_log, "browser", args.browser_context, args.event_limit
        )
    except RuntimeError as exc:
        return emit_fail(str(exc), native_log=args.native_log, browser_log=args.browser_log)

    diff = divergence_for(native, browser)
    timer_diff = timer_divergence_for(native, browser)
    mismatch_index, native_mismatch, browser_mismatch = first_mismatch(
        native.flow_events, browser.flow_events
    )
    native_vectors = native.vectors()
    browser_vectors = browser.vectors()
    native_extra = unique_extra(native_vectors, browser_vectors)
    browser_extra = unique_extra(browser_vectors, native_vectors)
    native_pic_ack_vectors = native.pic_ack_vectors()
    browser_pic_ack_vectors = browser.pic_ack_vectors()
    native_extra_pic_ack = unique_extra(native_pic_ack_vectors, browser_pic_ack_vectors)
    browser_extra_pic_ack = unique_extra(browser_pic_ack_vectors, native_pic_ack_vectors)
    native_first_extra_pic_ack = first_event_for_vector(
        native.pic_ack_events, native_extra_pic_ack
    )
    browser_first_extra_pic_ack = first_event_for_vector(
        browser.pic_ack_events, browser_extra_pic_ack
    )
    native_pic_line_assert_irqs = native.pic_line_assert_irqs()
    browser_pic_line_assert_irqs = browser.pic_line_assert_irqs()
    native_extra_pic_line_assert = unique_extra(
        native_pic_line_assert_irqs, browser_pic_line_assert_irqs
    )
    browser_extra_pic_line_assert = unique_extra(
        browser_pic_line_assert_irqs, native_pic_line_assert_irqs
    )
    native_first_extra_pic_line_assert = first_event_for_marker_field(
        native.pic_line_events, "guest_irq", native_extra_pic_line_assert
    )
    browser_first_extra_pic_line_assert = first_event_for_marker_field(
        browser.pic_line_events, "guest_irq", browser_extra_pic_line_assert
    )
    native_lpc_route_assert_irqs = native.lpc_route_assert_irqs()
    browser_lpc_route_assert_irqs = browser.lpc_route_assert_irqs()
    native_extra_lpc_route_assert = unique_extra(
        native_lpc_route_assert_irqs, browser_lpc_route_assert_irqs
    )
    browser_extra_lpc_route_assert = unique_extra(
        browser_lpc_route_assert_irqs, native_lpc_route_assert_irqs
    )
    native_first_extra_lpc_route_assert = first_event_for_marker_field(
        native.lpc_route_events, "pic_irq", native_extra_lpc_route_assert
    )
    browser_first_extra_lpc_route_assert = first_event_for_marker_field(
        browser.lpc_route_events, "pic_irq", browser_extra_lpc_route_assert
    )

    fields = {
        "result": "pass",
        "divergence": diff,
        "timer_divergence": timer_diff,
        "first_flow_mismatch_index": mismatch_index if mismatch_index >= 0 else "none",
        "native_flow_mismatch": (
            event_key(native_mismatch) if native_mismatch else "none"
        ),
        "browser_flow_mismatch": (
            event_key(browser_mismatch) if browser_mismatch else "none"
        ),
        "native_extra_vectors": compact_list(native_extra, args.list_limit),
        "browser_extra_vectors": compact_list(browser_extra, args.list_limit),
        "native_extra_pic_ack_vectors": compact_list(
            native_extra_pic_ack, args.list_limit
        ),
        "browser_extra_pic_ack_vectors": compact_list(
            browser_extra_pic_ack, args.list_limit
        ),
        "native_first_extra_pic_ack": (
            event_key(native_first_extra_pic_ack)
            if native_first_extra_pic_ack
            else "none"
        ),
        "browser_first_extra_pic_ack": (
            event_key(browser_first_extra_pic_ack)
            if browser_first_extra_pic_ack
            else "none"
        ),
        "native_extra_pic_line_assert_irqs": compact_list(
            native_extra_pic_line_assert, args.list_limit
        ),
        "browser_extra_pic_line_assert_irqs": compact_list(
            browser_extra_pic_line_assert, args.list_limit
        ),
        "native_first_extra_pic_line_assert": (
            event_key(native_first_extra_pic_line_assert)
            if native_first_extra_pic_line_assert
            else "none"
        ),
        "browser_first_extra_pic_line_assert": (
            event_key(browser_first_extra_pic_line_assert)
            if browser_first_extra_pic_line_assert
            else "none"
        ),
        "native_extra_lpc_route_assert_irqs": compact_list(
            native_extra_lpc_route_assert, args.list_limit
        ),
        "browser_extra_lpc_route_assert_irqs": compact_list(
            browser_extra_lpc_route_assert, args.list_limit
        ),
        "native_first_extra_lpc_route_assert": (
            event_key(native_first_extra_lpc_route_assert)
            if native_first_extra_lpc_route_assert
            else "none"
        ),
        "browser_first_extra_lpc_route_assert": (
            event_key(browser_first_extra_lpc_route_assert)
            if browser_first_extra_lpc_route_assert
            else "none"
        ),
    }
    fields.update(side_fields("native", native, args.list_limit))
    fields.update(side_fields("browser", browser, args.list_limit))
    fields["native_log"] = args.native_log
    fields["browser_log"] = args.browser_log

    print(
        "POST_IDLE_INTERRUPT_FLOW_COMPARE "
        + " ".join(f"{key}={value}" for key, value in fields.items())
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
