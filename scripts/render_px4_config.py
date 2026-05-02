#!/usr/bin/env python3
"""Render a PX4 /etc/config.txt overlay from a resolved matrix case.

The case JSON is expected to contain a 'resolved_airframe' key whose 'params'
sub-dictionary maps PX4 parameter names to numeric or string values.  This
script writes one `param set NAME VALUE` line per entry to stdout.  If the
case has no airframe, no output is produced (and the runner skips overlay
injection).
"""

import json
import sys


def render(case):
    airframe = case.get("resolved_airframe") or {}
    params = airframe.get("params", {}) or {}
    lines = [f"param set {name} {value}" for name, value in params.items()]
    return "\n".join(lines)


def main(argv):
    if len(argv) != 2:
        print("usage: render_px4_config.py <case.json>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        case = json.load(f)
    out = render(case)
    if out:
        print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
