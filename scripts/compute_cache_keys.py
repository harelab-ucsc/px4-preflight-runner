#!/usr/bin/env python3
"""Compute all preflight cache keys and print them as key=value lines
suitable for appending directly to $GITHUB_OUTPUT.

Every key is tied to a resolved commit SHA so floating refs (e.g. 'main')
bust the cache on upstream changes without requiring spec changes.

Outputs:
  px4_sha      - Commit SHA of PX4-Autopilot at px4_ref.
                 Used for the px4-sitl build cache and ccache keys.
  ros_deps_key - Short hash of px4_ref + ros_distro + resolved SHAs for
                 px4_msgs and every ros_workspace_extra entry.
                 Used for the ros-ext-ws colcon cache key.
"""

import hashlib
import json
import os
import re
import subprocess


def resolve_sha(url, version):
    """Return the commit SHA for a git ref, or the version string on failure."""
    if re.fullmatch(r"[0-9a-f]{40}", version.lower()):
        return version
    try:
        out = subprocess.check_output(
            ["git", "ls-remote", "--exit-code", url, version],
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
        return out.decode().splitlines()[0].split("\t")[0]
    except Exception:
        return version


def main():
    case = json.loads(os.environ["CASE_JSON"])
    px4_ref = case.get("px4_ref", "main")
    ros_distro = case.get("ros_distro", "humble")
    extra = case.get("ros_workspace_extra") or {}

    px4_sha = resolve_sha("https://github.com/PX4/PX4-Autopilot.git", px4_ref)

    m = re.match(r"^v(\d+)\.(\d+)", px4_ref)
    msgs_branch = f"release/{m.group(1)}.{m.group(2)}" if m else "main"
    msgs_sha = resolve_sha("https://github.com/PX4/px4_msgs.git", msgs_branch)

    resolved_extra = {}
    for name in sorted(extra):
        entry = dict(extra[name])
        entry["version"] = resolve_sha(entry.get("url", ""), entry.get("version", ""))
        resolved_extra[name] = entry

    blob = f"{px4_ref}-{ros_distro}-{msgs_sha}-{json.dumps(resolved_extra, sort_keys=True)}"
    ros_deps_key = hashlib.sha256(blob.encode()).hexdigest()[:16]

    print(f"px4_sha={px4_sha}")
    print(f"ros_deps_key={ros_deps_key}")


if __name__ == "__main__":
    main()
