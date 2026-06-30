#!/usr/bin/env python3
"""Compare native/browser B6 post-command NV2A IRQ and PMC state."""

import argparse
import sys
from collections import Counter
from dataclasses import dataclass, field


def line_value(line, key, default=""):
    prefix = f"{key}="
    for token in line.split():
        if token.startswith(prefix):
            return token[len(prefix):].strip('"')
    return default


def line_value_any(line, keys, default=""):
    for key in keys:
        value = line_value(line, key, "")
        if value:
            return value
    return default


def bool_word(value):
    return "yes" if value else "no"


def is_stream_idle_pfifo_window(line):
    if not line.startswith("BOOT_MARK b6 pfifo=window "):
        return False
    if line_value(line, "op", "none") != "pusher-empty":
        return False
    dma_get = line_value(line, "dma_get", "none")
    dma_put = line_value(line, "dma_put", "none")
    return dma_get != "none" and dma_get == dma_put


@dataclass
class ParsedIrqLog:
    label: str
    stream_idle_count: int = 0
    first_idle_line_no: int = 0
    latest_idle_line_no: int = 0
    latest_idle_line: str = ""
    after_idle_loop_count: int = 0
    latest_after_idle_loop_line_no: int = 0
    latest_after_idle_loop: str = ""
    pmc_access_count: int = 0
    pmc_access_after_idle_count: int = 0
    pmc_enable_after_idle_count: int = 0
    pmc_disable_after_idle_count: int = 0
    latest_pmc_access: str = ""
    latest_after_idle_pmc_access: str = ""
    latest_after_idle_pmc_enable: str = ""
    latest_after_idle_pmc_disable: str = ""
    irq_source_counts: Counter = field(default_factory=Counter)
    irq_source_after_idle_counts: Counter = field(default_factory=Counter)
    latest_irq_source: str = ""
    latest_after_idle_irq_source: str = ""
    irq_line_count: int = 0
    irq_line_after_idle_count: int = 0
    latest_irq_line: str = ""
    latest_after_idle_irq_line: str = ""

    def stream_idle_seen(self):
        return self.stream_idle_count > 0

    def after_idle_seen(self, line):
        return self.stream_idle_seen() or line_value(line, "stream_idle", "no") == "yes"

    def after_idle_loop_seen(self):
        return self.after_idle_loop_count > 0

    def latest_loop_pmc_enabled(self):
        return line_value(self.latest_after_idle_loop, "nv2a_pmc_enabled", "none")

    def latest_loop_pmc_pending(self):
        return line_value(self.latest_after_idle_loop, "nv2a_pmc_pending", "none")

    def pcrtc_after_idle_count(self, op):
        return self.irq_source_after_idle_counts[("pcrtc", op)]

    def pgraph_after_idle_count(self, op):
        return self.irq_source_after_idle_counts[("pgraph", op)]


def fail(reason, **fields):
    parts = [f"POST_COMMAND_IRQ_STATE_COMPARE result=fail reason={reason}"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts), file=sys.stderr)
    return 1


def parse_log(path, label, context):
    parsed = ParsedIrqLog(label=label)

    try:
        with open(path, "r", encoding="utf-8", errors="replace") as log:
            for line_no, raw_line in enumerate(log, 1):
                line = raw_line.rstrip("\n")
                if context and f"context={context}" not in line:
                    continue

                if is_stream_idle_pfifo_window(line):
                    parsed.stream_idle_count += 1
                    if not parsed.first_idle_line_no:
                        parsed.first_idle_line_no = line_no
                    parsed.latest_idle_line_no = line_no
                    parsed.latest_idle_line = line
                    continue

                if line.startswith("BOOT_MARK b6 dashboard=kernel-loop-probe "):
                    if parsed.after_idle_seen(line):
                        parsed.after_idle_loop_count += 1
                        parsed.latest_after_idle_loop_line_no = line_no
                        parsed.latest_after_idle_loop = line
                    continue

                if line.startswith("BOOT_MARK b6 nv2a=pmc-access "):
                    parsed.pmc_access_count += 1
                    parsed.latest_pmc_access = line
                    if parsed.stream_idle_seen():
                        parsed.pmc_access_after_idle_count += 1
                        parsed.latest_after_idle_pmc_access = line
                        if (
                            line_value(line, "op", "none") == "write"
                            and line_value(line, "reg", "none") == "NV_PMC_INTR_EN_0"
                        ):
                            if line_value(line, "value", "none") == "0x00000001":
                                parsed.pmc_enable_after_idle_count += 1
                                parsed.latest_after_idle_pmc_enable = line
                            elif line_value(line, "value", "none") == "0x00000000":
                                parsed.pmc_disable_after_idle_count += 1
                                parsed.latest_after_idle_pmc_disable = line
                    continue

                if line.startswith("BOOT_MARK b6 nv2a=irq-source "):
                    source = line_value(line, "source", "none")
                    op = line_value(line, "op", "none")
                    parsed.irq_source_counts[(source, op)] += 1
                    parsed.latest_irq_source = line
                    if parsed.stream_idle_seen():
                        parsed.irq_source_after_idle_counts[(source, op)] += 1
                        parsed.latest_after_idle_irq_source = line
                    continue

                if line.startswith("BOOT_MARK b6 nv2a=irq-line "):
                    parsed.irq_line_count += 1
                    parsed.latest_irq_line = line
                    if parsed.stream_idle_seen():
                        parsed.irq_line_after_idle_count += 1
                        parsed.latest_after_idle_irq_line = line
    except OSError as exc:
        raise RuntimeError(f"{label} log unreadable: {exc}") from exc

    return parsed


def divergence_for(native, browser):
    if not native.stream_idle_seen() or not browser.stream_idle_seen():
        return "command-stream-not-idle"
    if not native.after_idle_loop_seen() and not browser.after_idle_loop_seen():
        return "no-after-idle-loop-samples"
    if not native.after_idle_loop_seen():
        return "native-no-after-idle-loop-samples"
    if not browser.after_idle_loop_seen():
        return "browser-no-after-idle-loop-samples"

    native_pmc_enabled = native.latest_loop_pmc_enabled()
    browser_pmc_enabled = browser.latest_loop_pmc_enabled()
    if native_pmc_enabled != browser_pmc_enabled:
        if browser_pmc_enabled == "0x00000000":
            return "browser-pmc-disabled-after-idle"
        return "pmc-enabled-mismatch"

    native_vblank = native.pcrtc_after_idle_count("vblank-raise")
    browser_vblank = browser.pcrtc_after_idle_count("vblank-raise")
    if browser_vblank > native_vblank:
        return "browser-pcrtc-vblank-after-idle"

    native_loop_start = line_value(native.latest_after_idle_loop, "start_pc", "none")
    browser_loop_start = line_value(browser.latest_after_idle_loop, "start_pc", "none")
    native_loop_next = line_value(native.latest_after_idle_loop, "next_pc", "none")
    browser_loop_next = line_value(browser.latest_after_idle_loop, "next_pc", "none")
    if (native_loop_start, native_loop_next) != (browser_loop_start, browser_loop_next):
        return "post-command-loop-mismatch"

    return "same-irq-state"


def add_line_fields(fields, prefix, line):
    fields.update(
        {
            f"{prefix}_op": line_value(line, "op", "none"),
            f"{prefix}_source": line_value(line, "source", "none"),
            f"{prefix}_reg": line_value(line, "reg", "none"),
            f"{prefix}_value": line_value(line, "value", "none"),
            f"{prefix}_pmc_pending_before": line_value(
                line, "pmc_pending_before", line_value(line, "pmc_pending", "none")
            ),
            f"{prefix}_pmc_enabled_before": line_value(
                line, "pmc_enabled_before", line_value(line, "pmc_enabled", "none")
            ),
            f"{prefix}_pmc_pending_after": line_value_any(
                line, ("pmc_pending_after", "pmc_pending"), "none"
            ),
            f"{prefix}_pmc_enabled_after": line_value_any(
                line, ("pmc_enabled_after", "pmc_enabled"), "none"
            ),
            f"{prefix}_pcrtc_pending_after": line_value_any(
                line, ("pcrtc_pending_after", "pcrtc_pending"), "none"
            ),
            f"{prefix}_pcrtc_enabled_after": line_value_any(
                line, ("pcrtc_enabled_after", "pcrtc_enabled"), "none"
            ),
            f"{prefix}_pgraph_pending_after": line_value_any(
                line, ("pgraph_pending_after", "pgraph_pending"), "none"
            ),
            f"{prefix}_pgraph_enabled_after": line_value_any(
                line, ("pgraph_enabled_after", "pgraph_enabled"), "none"
            ),
            f"{prefix}_cpu_known": line_value(line, "cpu_known", "unknown"),
            f"{prefix}_cpu_source": line_value(line, "cpu_source", "none"),
            f"{prefix}_cpu_mode": line_value(line, "cpu_mode", "none"),
            f"{prefix}_cpl": line_value(line, "cpl", "none"),
            f"{prefix}_eip": line_value(line, "eip", "none"),
            f"{prefix}_cs": line_value(line, "cs", "none"),
            f"{prefix}_esp": line_value(line, "esp", "none"),
            f"{prefix}_eflags": line_value(line, "eflags", "none"),
            f"{prefix}_interrupts_enabled": line_value(
                line, "interrupts_enabled", "unknown"
            ),
            f"{prefix}_irq_inhibited": line_value(
                line, "irq_inhibited", "unknown"
            ),
            f"{prefix}_cpu_interrupt_request": line_value(
                line, "cpu_interrupt_request", "none"
            ),
            f"{prefix}_pending_interrupt": line_value(
                line, "pending_interrupt", "unknown"
            ),
            f"{prefix}_cpu_halted": line_value(line, "cpu_halted", "unknown"),
            f"{prefix}_cpu_exit_request": line_value(
                line, "cpu_exit_request", "unknown"
            ),
            f"{prefix}_cpu_exception_index": line_value(
                line, "cpu_exception_index", "none"
            ),
        }
    )


def add_side_fields(fields, prefix, parsed):
    loop_line = parsed.latest_after_idle_loop
    idle_line = parsed.latest_idle_line

    fields.update(
        {
            f"{prefix}_stream_idle_seen": bool_word(parsed.stream_idle_seen()),
            f"{prefix}_stream_idle_count": parsed.stream_idle_count,
            f"{prefix}_first_idle_line": parsed.first_idle_line_no or "none",
            f"{prefix}_latest_idle_line": parsed.latest_idle_line_no or "none",
            f"{prefix}_idle_pmc_pending": line_value(
                idle_line, "pmc_pending", "none"
            ),
            f"{prefix}_idle_pmc_enabled": line_value(
                idle_line, "pmc_enabled", "none"
            ),
            f"{prefix}_after_idle_loops": parsed.after_idle_loop_count,
            f"{prefix}_after_idle_loop_line": (
                parsed.latest_after_idle_loop_line_no or "none"
            ),
            f"{prefix}_loop_start": line_value(loop_line, "start_pc", "none"),
            f"{prefix}_loop_next": line_value(loop_line, "next_pc", "none"),
            f"{prefix}_loop_kind": line_value(loop_line, "loop_kind", "none"),
            f"{prefix}_loop_pmc_pending": parsed.latest_loop_pmc_pending(),
            f"{prefix}_loop_pmc_enabled": parsed.latest_loop_pmc_enabled(),
            f"{prefix}_loop_pcrtc_pending": line_value(
                loop_line, "nv2a_pcrtc_pending", "none"
            ),
            f"{prefix}_loop_pcrtc_enabled": line_value(
                loop_line, "nv2a_pcrtc_enabled", "none"
            ),
            f"{prefix}_loop_pgraph_pending": line_value(
                loop_line, "nv2a_pgraph_pending", "none"
            ),
            f"{prefix}_loop_pgraph_enabled": line_value(
                loop_line, "nv2a_pgraph_enabled", "none"
            ),
            f"{prefix}_loop_start_mem_kind": line_value(
                loop_line, "start_mem_kind", "none"
            ),
            f"{prefix}_loop_start_mem_addr": line_value(
                loop_line, "start_mem_addr", "none"
            ),
            f"{prefix}_loop_start_mem_region": line_value(
                loop_line, "start_mem_region", "none"
            ),
            f"{prefix}_loop_start_mem_value_read": line_value(
                loop_line, "start_mem_value_read", "unknown"
            ),
            f"{prefix}_loop_start_mem_value": line_value(
                loop_line, "start_mem_value", "none"
            ),
            f"{prefix}_loop_next_mem_kind": line_value(
                loop_line, "next_mem_kind", "none"
            ),
            f"{prefix}_loop_next_mem_addr": line_value(
                loop_line, "next_mem_addr", "none"
            ),
            f"{prefix}_loop_next_mem_region": line_value(
                loop_line, "next_mem_region", "none"
            ),
            f"{prefix}_loop_next_mem_value_read": line_value(
                loop_line, "next_mem_value_read", "unknown"
            ),
            f"{prefix}_loop_next_mem_value": line_value(
                loop_line, "next_mem_value", "none"
            ),
            f"{prefix}_pmc_access": parsed.pmc_access_count,
            f"{prefix}_pmc_after_idle": parsed.pmc_access_after_idle_count,
            f"{prefix}_pmc_after_idle_enable_writes": (
                parsed.pmc_enable_after_idle_count
            ),
            f"{prefix}_pmc_after_idle_disable_writes": (
                parsed.pmc_disable_after_idle_count
            ),
            f"{prefix}_pcrtc_vblank_raise": parsed.irq_source_counts[
                ("pcrtc", "vblank-raise")
            ],
            f"{prefix}_pcrtc_vblank_raise_after_idle": (
                parsed.pcrtc_after_idle_count("vblank-raise")
            ),
            f"{prefix}_pcrtc_intr_clear": parsed.irq_source_counts[
                ("pcrtc", "intr-clear")
            ],
            f"{prefix}_pcrtc_intr_clear_after_idle": (
                parsed.pcrtc_after_idle_count("intr-clear")
            ),
            f"{prefix}_pgraph_intr_clear": parsed.irq_source_counts[
                ("pgraph", "intr-clear")
            ],
            f"{prefix}_pgraph_intr_clear_after_idle": (
                parsed.pgraph_after_idle_count("intr-clear")
            ),
            f"{prefix}_irq_line": parsed.irq_line_count,
            f"{prefix}_irq_line_after_idle": parsed.irq_line_after_idle_count,
        }
    )

    add_line_fields(fields, f"{prefix}_latest_pmc", parsed.latest_pmc_access)
    add_line_fields(
        fields, f"{prefix}_latest_after_idle_pmc", parsed.latest_after_idle_pmc_access
    )
    add_line_fields(
        fields, f"{prefix}_latest_after_idle_pmc_enable",
        parsed.latest_after_idle_pmc_enable,
    )
    add_line_fields(
        fields, f"{prefix}_latest_after_idle_pmc_disable",
        parsed.latest_after_idle_pmc_disable,
    )
    add_line_fields(fields, f"{prefix}_latest_irq", parsed.latest_irq_source)
    add_line_fields(
        fields, f"{prefix}_latest_after_idle_irq", parsed.latest_after_idle_irq_source
    )
    add_line_fields(fields, f"{prefix}_latest_irq_line", parsed.latest_irq_line)
    add_line_fields(
        fields, f"{prefix}_latest_after_idle_irq_line", parsed.latest_after_idle_irq_line
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Summarize native/browser post-command NV2A interrupt state "
            "without reading or dumping proprietary asset bytes."
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

    if not native.stream_idle_seen():
        return fail("missing-native-stream-idle", native_log=args.native_log)
    if not browser.stream_idle_seen():
        return fail("missing-browser-stream-idle", browser_log=args.browser_log)
    if not native.after_idle_loop_seen():
        return fail("missing-native-after-idle-loop", native_log=args.native_log)
    if not browser.after_idle_loop_seen():
        return fail("missing-browser-after-idle-loop", browser_log=args.browser_log)

    divergence = divergence_for(native, browser)
    fields = {
        "divergence": divergence,
        "both_stream_idle": bool_word(
            native.stream_idle_seen() and browser.stream_idle_seen()
        ),
        "both_after_idle_loop": bool_word(
            native.after_idle_loop_seen() and browser.after_idle_loop_seen()
        ),
        "same_loop_pmc_enabled": bool_word(
            native.latest_loop_pmc_enabled() == browser.latest_loop_pmc_enabled()
        ),
        "same_loop_pmc_pending": bool_word(
            native.latest_loop_pmc_pending() == browser.latest_loop_pmc_pending()
        ),
    }
    add_side_fields(fields, "native", native)
    add_side_fields(fields, "browser", browser)
    fields.update(
        {
            "native_log": args.native_log,
            "browser_log": args.browser_log,
        }
    )

    parts = ["POST_COMMAND_IRQ_STATE_COMPARE result=pass"]
    parts.extend(f"{key}={value}" for key, value in fields.items())
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
