#!/usr/bin/env python3
"""Summarize complete eight-state documentation UI timings; never infer a speedup."""
import argparse
import itertools
import json
import math
import re
from pathlib import Path

STATES = {f"{locale}-{appearance}-{size}" for locale, appearance, size in
          itertools.product(("en", "es"), ("light", "dark"), ("minimum", "1280"))}
PHASES = ("launch", "navigation", "description", "package-setup", "panel", "export", "validation", "termination")
PATTERN = re.compile(r"DOCUMENTATION_UI_SEGMENT state=(\S+) phase=(\S+) seconds=(\S+)")


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


def self_test():
    valid = "\n".join(f"DOCUMENTATION_UI_SEGMENT state={s} phase={p} seconds=1.25"
                      for s in sorted(STATES) for p in PHASES)
    assert summarize(valid)["total_seconds"] == 80
    for invalid in ("", valid.split("\n", 1)[1], valid + "\n" + valid.splitlines()[0],
                    valid.replace("seconds=1.25", "seconds=nan", 1),
                    valid.replace("seconds=1.25", "seconds=-1", 1),
                    valid.replace("state=en-dark-1280", "state=unknown", 1),
                    valid.replace("phase=launch", "phase=unknown", 1)):
        try:
            summarize(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed/incomplete timing evidence was accepted")
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
            print(json.dumps(summarize(args.log.read_text()), indent=2))
        except (ValueError, OSError) as error:
            parser.exit(1, f"Invalid documentation UI timing evidence: {error}\n")
    else:
        parser.error("provide one complete job log or --self-test")
