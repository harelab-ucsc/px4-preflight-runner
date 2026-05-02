#!/usr/bin/env python3
"""Map a PX4-Autopilot release tag to the matching px4_msgs branch.

Examples:
    v1.16.0  -> release/1.16
    v1.14.3  -> release/1.14
    main     -> main  (fallback when tag is not a release tag)
"""

import re
import sys


def resolve(tag):
    m = re.match(r"^v(\d+)\.(\d+)(?:\.\d+)?$", tag.strip())
    if not m:
        return "main"
    return f"release/{m.group(1)}.{m.group(2)}"


def main(argv):
    if len(argv) != 2:
        print("usage: resolve_px4_msgs_ref.py <px4_tag>", file=sys.stderr)
        return 2
    print(resolve(argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
