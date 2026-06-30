#!/usr/bin/env python3
"""Compare native/browser PCRTC vblank timing in B6 dashboard diagnostics."""

import argparse
import sys
from collections import Counter
from dataclasses import dataclass, field


PMC_PCRTC_BIT = 0x01000000
PMC_PGRAPH_BIT = 0x00001000


def line_value(line, key, default=""):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return default


def hex_value(line, key, default=0):
    value = line_value(line, key, "")
    if not value:
        return default
    try:
        return int(value, 0)
    except ValueError:
        return default


def is_stream_idle_pfifo_window(line):
    if not line.startswith("BOOT_MARK b6 pfifo=window "):
        return False
    if line_value(line, "op", "none") != "pusher-empty":
        return False
    dma_get = line_value(line, "dma_get", "none")
    dma_put = line_value(line, "dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


def phase_for(parsed):
    if not parsed.xbe_loaded_line:
        return "before_xbe"
    if not parsed.entry_ready_line:
        return "xbe_to_ready"
    if not parsed.stream_idle_line:
        return "ready_to_idle"
    return "after_idle"


@dataclass
class ParsedVblankLog:
    label: str
    xbe_loaded_line: int = 0
    entry_ready_line: int = 0
    stream_idle_line: int = 0
    first_pcrtc_enable_line: str = ""
    first_pcrtc_enable_line_no: int = 0
    first_vblank_line_no: int = 0
    latest_vblank_line_no: int = 0
    latest_vblank_line: str = ""
    latest_pcrtc_clear_line: str = ""
    latest_pmc_disable_line: str = ""
    latest_pmc_enable_line: str = ""
    pcrtc_vblank_by_phase: Counter = field(default_factory=Counter)
    pcrtc_clear_by_phase: Counter = field(default_factory=Counter)
    pcrtc_enable_by_phase: Counter = field(default_factory=Counter)
    pmc_disable_by_phase: Counter = field(default_factory=Counter)
    pmc_enable_by_phase: Counter = field(default_factory=Counter)
    pmc_disable_source: Counter = field(default_factory=Counter)

    def vblank_total(self):
        return sum(self.pcrtc_vblank_by_phase.values())

    def clear_total(self):
        return sum(self.pcrtc_clear_by_phase.values())

    def pmc_disable_total(self):
        return sum(self.pmc_disable_by_phase.values())

    def pmc_enable_total(self):
        return sum(self.pmc_enable_by_phase.values())

    def first_pcrtc_pending_before(self):
        return line_value(self.first_pcrtc_enable_line, "pcrtc_pending_before", "none")


def classify_pmc_disable(line):
    pmc_pending = hex_value(line, "pmc_pending_before") | hex_value(line, "pmc_pending_after")
    pcrtc_pending = hex_value(line, "pcrtc_pending")
    pgraph_pending = hex_value(line, "pgraph_pending")

    if pcrtc_pending or (pmc_pending & PMC_PCRTC_BIT):
        return "pcrtc"
    if pgraph_pending or (pmc_pending & PMC_PGRAPH_BIT):
        return "pgraph"
    if pmc_pending:
        return "other"
    return "none"


def parse_log(path, label, context):
    parsed = ParsedVblankLog(label=label)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                line = raw_line.rstrip("\n")
                if context and f"context={context}" not in line:
                    continue

                if line.startswith("BOOT_MARK b6 dashboard=xbe-loaded "):
                    if not parsed.xbe_loaded_line:
                        parsed.xbe_loaded_line = line_no
                    continue

                if (
                    line.startswith("BOOT_MARK b6 dashboard=xbe-entry-probe ")
                    and line_value(line, "status", "none") == "ready"
                ):
                    if not parsed.entry_ready_line:
                        parsed.entry_ready_line = line_no
                    continue

                if is_stream_idle_pfifo_window(line):
                    if not parsed.stream_idle_line:
                        parsed.stream_idle_line = line_no
                    continue

                if line.startswith("BOOT_MARK b6 nv2a=irq-source "):
                    source = line_value(line, "source", "none")
                    op = line_value(line, "op", "none")
                    if source != "pcrtc":
                        continue

                    phase = phase_for(parsed)
                    if op == "intr-enable":
                        parsed.pcrtc_enable_by_phase[phase] += 1
                        if not parsed.first_pcrtc_enable_line:
                            parsed.first_pcrtc_enable_line = line
                            parsed.first_pcrtc_enable_line_no = line_no
                    elif op == "vblank-raise":
                        parsed.pcrtc_vblank_by_phase[phase] += 1
                        if not parsed.first_vblank_line_no:
                            parsed.first_vblank_line_no = line_no
                        parsed.latest_vblank_line_no = line_no
                        parsed.latest_vblank_line = line
                    elif op == "intr-clear":
                        parsed.pcrtc_clear_by_phase[phase] += 1
                        parsed.latest_pcrtc_clear_line = line
                    continue

                if line.startswith("BOOT_MARK b6 nv2a=pmc-access "):
                    if (
                        line_value(line, "op", "none") != "write"
                        or line_value(line, "reg", "none") != "NV_PMC_INTR_EN_0"
                    ):
                        continue
                    phase = phase_for(parsed)
                    value = line_value(line, "value", "none")
                    if value == "0x00000000":
                        parsed.pmc_disable_by_phase[phase] += 1
                        parsed.pmc_disable_source[classify_pmc_disable(line)] += 1
                        parsed.latest_pmc_disable_line = line
                    elif value == "0x00000001":
                        parsed.pmc_enable_by_phase[phase] += 1
                        parsed.latest_pmc_enable_line = line
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc
    return parsed


def divergence_for(native, browser):
    native_first = native.first_pcrtc_pending_before()
    browser_first = browser.first_pcrtc_pending_before()
    if native_first != browser_first and browser_first not in ("none", "0x00000000"):
        return "browser-initial-pcrtc-pending"
    if browser.pcrtc_vblank_by_phase["before_xbe"] > native.pcrtc_vblank_by_phase["before_xbe"]:
        return "browser-extra-pcrtc-vblank-before-xbe"
    if browser.pcrtc_vblank_by_phase["xbe_to_ready"] > native.pcrtc_vblank_by_phase["xbe_to_ready"]:
        return "browser-extra-pcrtc-vblank-before-entry-ready"
    if browser.pcrtc_vblank_by_phase["ready_to_idle"] > native.pcrtc_vblank_by_phase["ready_to_idle"]:
        return "browser-extra-pcrtc-vblank-before-idle"
    if browser.pcrtc_vblank_by_phase["after_idle"] > native.pcrtc_vblank_by_phase["after_idle"]:
        return "browser-extra-pcrtc-vblank-after-idle"
    if browser.pmc_disable_source["pcrtc"] > native.pmc_disable_source["pcrtc"]:
        return "browser-pmc-disable-pcrtc"
    return "same-pcrtc-vblank-shape"


def add_parsed_fields(fields, prefix, parsed):
    phases = ("before_xbe", "xbe_to_ready", "ready_to_idle", "after_idle")
    fields.update(
        {
            f"{prefix}_xbe_loaded_line": parsed.xbe_loaded_line,
            f"{prefix}_entry_ready_line": parsed.entry_ready_line,
            f"{prefix}_stream_idle_line": parsed.stream_idle_line,
            f"{prefix}_first_pcrtc_enable_line": parsed.first_pcrtc_enable_line_no,
            f"{prefix}_first_pcrtc_pending_before": parsed.first_pcrtc_pending_before(),
            f"{prefix}_first_vblank_line": parsed.first_vblank_line_no,
            f"{prefix}_latest_vblank_line": parsed.latest_vblank_line_no,
            f"{prefix}_pcrtc_vblank": parsed.vblank_total(),
            f"{prefix}_pcrtc_clear": parsed.clear_total(),
            f"{prefix}_pmc_disable": parsed.pmc_disable_total(),
            f"{prefix}_pmc_enable": parsed.pmc_enable_total(),
            f"{prefix}_pmc_disable_pcrtc": parsed.pmc_disable_source["pcrtc"],
            f"{prefix}_pmc_disable_pgraph": parsed.pmc_disable_source["pgraph"],
            f"{prefix}_pmc_disable_other": parsed.pmc_disable_source["other"],
            f"{prefix}_pmc_disable_none": parsed.pmc_disable_source["none"],
            f"{prefix}_latest_pmc_disable_eip": line_value(parsed.latest_pmc_disable_line, "eip", "none"),
            f"{prefix}_latest_pmc_enable_eip": line_value(parsed.latest_pmc_enable_line, "eip", "none"),
        }
    )
    for phase in phases:
        fields[f"{prefix}_vblank_{phase}"] = parsed.pcrtc_vblank_by_phase[phase]
        fields[f"{prefix}_clear_{phase}"] = parsed.pcrtc_clear_by_phase[phase]
        fields[f"{prefix}_pmc_disable_{phase}"] = parsed.pmc_disable_by_phase[phase]
        fields[f"{prefix}_pmc_enable_{phase}"] = parsed.pmc_enable_by_phase[phase]


def fail(reason, **fields):
    parts = [f"PCRTC_VBLANK_DIVERGENCE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-log", required=True)
    parser.add_argument("--browser-log", required=True)
    parser.add_argument("--native-context", default="native-headless")
    parser.add_argument("--browser-context", default="browser-runtime")
    args = parser.parse_args(argv)

    try:
        native = parse_log(args.native_log, "native", args.native_context)
        browser = parse_log(args.browser_log, "browser", args.browser_context)
    except RuntimeError as exc:
        return fail(str(exc))

    fields = {"divergence": divergence_for(native, browser)}
    add_parsed_fields(fields, "native", native)
    add_parsed_fields(fields, "browser", browser)
    fields["native_log"] = args.native_log
    fields["browser_log"] = args.browser_log

    parts = ["PCRTC_VBLANK_DIVERGENCE result=pass"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
