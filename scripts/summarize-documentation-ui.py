#!/usr/bin/env python3
"""Summarize complete eight-state documentation UI timings; never infer a speedup."""
import argparse
import itertools
import json
import math
import re
from pathlib import Path

LOCALES = ("en", "es")
APPEARANCES = ("light", "dark")
SIZES = ("minimum", "1280")
STATES = {f"{locale}-{appearance}-{size}" for locale, appearance, size in
          itertools.product(LOCALES, APPEARANCES, SIZES)}
PHASES = ("launch", "navigation", "description", "package-setup", "panel", "export", "validation", "termination")
PATTERN = re.compile(r"DOCUMENTATION_UI_SEGMENT state=(\S+) phase=(\S+) seconds=(\S+)")
# The test that emits the markers; its labels must stay in lockstep with the constants above.
SOURCE = Path(__file__).resolve().parent.parent / "UITests" / "DocumentationExportUITests.swift"


def summarize(text):
    states = {state: {} for state in STATES}
    for state, phase, raw in PATTERN.findall(text):
        if state not in STATES or phase not in PHASES:
            raise ValueError(f"Unknown state or phase: {state}/{phase}")
        if phase in states[state]:
            raise ValueError(f"Duplicate timing: {state}/{phase}; provide one job attempt only")
        seconds = float(raw)
        if not math.isfinite(seconds) or seconds < 0:
            raise ValueError(f"Invalid duration: {raw}")
        states[state][phase] = seconds
    for state, phases in states.items():
        if set(phases) != set(PHASES):
            raise ValueError(f"Incomplete state {state}: missing {sorted(set(PHASES) - phases.keys())}")
    totals = {phase: sum(states[state][phase] for state in STATES) for phase in PHASES}
    return {"states": dict(sorted(states.items())), "phase_seconds": totals,
            "total_seconds": sum(totals.values()), "state_count": len(states),
            "qualification": "diagnostic timings only; no controlled performance improvement claim"}


def check_source(source):
    """Fail when the UI test's marker labels drift from the constants the summarizer expects."""
    phases = tuple(re.findall(r'recordSegment\("([^"]+)"\)', source))
    languages = re.search(r"for language in \[([^\]]+)\]", source)
    locales = tuple(re.findall(r'"([^"]+)"', languages.group(1) if languages else ""))
    ternary = re.search(r'dark \? "([^"]+)" : "([^"]+)"', source)
    appearances = (ternary.group(2), ternary.group(1)) if ternary else ()
    sizes = tuple(re.findall(r'label: "([^"]+)"', source))
    found = (phases, locales, appearances, sizes)
    if found != (PHASES, LOCALES, APPEARANCES, SIZES):
        raise ValueError(f"Test marker labels {found} differ from summarizer labels "
                         f"{(PHASES, LOCALES, APPEARANCES, SIZES)}")


def self_test():
    check_source(SOURCE.read_text(encoding="utf-8"))
    valid = "\n".join(f"DOCUMENTATION_UI_SEGMENT state={s} phase={p} seconds=1.25"
                      for s in sorted(STATES) for p in PHASES)
    if summarize(valid)["total_seconds"] != 80:
        raise AssertionError("Complete timing evidence was not summed correctly")
    for invalid in ("", valid.split("\n", 1)[1], valid + "\n" + valid.splitlines()[0],
                    valid.replace("seconds=1.25", "seconds=nan", 1),
                    valid.replace("seconds=1.25", "seconds=-1", 1),
                    valid.replace("seconds=1.25", "seconds=soon", 1),
                    valid + "\nDOCUMENTATION_UI_SEGMENT state=unknown phase=launch seconds=1.25",
                    valid + "\nDOCUMENTATION_UI_SEGMENT state=en-dark-1280 phase=unknown seconds=1.25"):
        try:
            summarize(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed/incomplete timing evidence was accepted")
    for drifted in (SOURCE.read_text(encoding="utf-8").replace('recordSegment("panel")', 'recordSegment("dialog")'),
                    SOURCE.read_text(encoding="utf-8").replace('label: "1280"', 'label: "large"')):
        try:
            check_source(drifted)
        except ValueError:
            pass
        else:
            raise AssertionError("Drifted test marker labels were accepted")
    print("documentation UI timing self-tests passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.log:
        try:
            # Marker lines are ASCII; a stray byte elsewhere in a large job log is not evidence.
            text = args.log.read_text(encoding="utf-8", errors="replace")
            print(json.dumps(summarize(text), indent=2))
        except (ValueError, OSError) as error:
            parser.exit(1, f"Invalid documentation UI timing evidence: {error}\n")
    else:
        parser.error("provide one complete job log or --self-test")
