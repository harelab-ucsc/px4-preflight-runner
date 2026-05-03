#!/usr/bin/env python3
"""Print a 16-char hex cache key for the ROS external deps workspace.

Reads CASE_JSON from the environment. Resolves every repo's version ref to
its actual commit SHA via git ls-remote so that pushes to floating refs
(e.g. 'main') bust the cache without requiring spec.yaml changes.
"""

import hashlib
import json
import os
import re
import subprocess


def resolve_sha(url, version):
    """Return the commit SHA for a git ref.

    Returns the version string unchanged if it is already a full SHA or if
    ls-remote fails (network issue, private repo, etc.).
    """
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

    m = re.match(r"^v(\d+)\.(\d+)", px4_ref)
    msgs_branch = f"release/{m.group(1)}.{m.group(2)}" if m else "main"
    msgs_sha = resolve_sha("https://github.com/PX4/px4_msgs.git", msgs_branch)

    resolved = {}
    for name in sorted(extra):
        entry = dict(extra[name])
        entry["version"] = resolve_sha(entry.get("url", ""), entry.get("version", ""))
        resolved[name] = entry

    blob = f"{px4_ref}-{ros_distro}-{msgs_sha}-{json.dumps(resolved, sort_keys=True)}"
    print(hashlib.sha256(blob.encode()).hexdigest()[:16])


if __name__ == "__main__":
    main()
