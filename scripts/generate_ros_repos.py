#!/usr/bin/env python3
"""Generate a vcs-tool '.repos' file for the ROS workspace under test.

Inputs:
  argv[1]  Path to a JSON file containing one matrix case (with px4_ref,
           ros_workspace_extra, etc.).
  argv[2]  Absolute path to the caller repo on disk; it is added to the
           workspace as a local 'path' source named 'caller_repo'.

The px4_msgs branch is derived from the case's px4_ref using
resolve_px4_msgs_ref so that the message definitions match the PX4 release
under test.
"""

import json
import os
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def derive_msgs_ref(px4_ref):
    out = subprocess.check_output(
        [sys.executable, os.path.join(HERE, "resolve_px4_msgs_ref.py"), px4_ref]
    )
    return out.decode().strip()


def build_repos(case, repo_root):
    """Return a vcs-tool .repos mapping.

    Note: the caller repo itself is *not* included — vcs-tool only supports
    git/hg/bzr/svn URLs, not local paths. The runner script copies/symlinks
    the caller's src/ tree into the workspace separately.
    """
    px4_ref = case.get("px4_ref", "main")
    extra = case.get("ros_workspace_extra", {}) or {}

    repos = {
        "repositories": {
            "px4_msgs": {
                "type": "git",
                "url": "https://github.com/PX4/px4_msgs.git",
                "version": derive_msgs_ref(px4_ref),
            },
        }
    }
    for name, entry in extra.items():
        repos["repositories"][name] = entry
    # repo_root is accepted for API stability but unused here.
    _ = repo_root
    return repos


def main(argv):
    if len(argv) != 3:
        print("usage: generate_ros_repos.py <case.json> <repo_root>", file=sys.stderr)
        return 2
    with open(argv[1]) as f:
        case = json.load(f)
    repo_root = os.path.abspath(argv[2])
    repos = build_repos(case, repo_root)
    print(yaml.safe_dump(repos, sort_keys=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
