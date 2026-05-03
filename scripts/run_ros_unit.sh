#!/usr/bin/env bash
# Build the caller's ROS workspace with a version-matched px4_msgs and run
# colcon test on the requested packages.
set -eo pipefail

: "${CASE_FILE:?}"
: "${REPO_ROOT:?}"
: "${SCRIPTS:?}"
: "${ROS_DISTRO:?}"
: "${PACKAGES:?}"

# ROS setup scripts reference unset vars; only enable nounset after sourcing.
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"
set -u

# ──────────────────────────────────────────────────────────────────────────
# External ROS deps: px4_msgs + ros_workspace_extra
# Cached at /opt/ros_external_ws by actions/cache in run-case/action.yml.
# On a cache hit the directory is already populated; we just source it.
# On a cache miss we build it so actions/cache saves it for the next run.
# ──────────────────────────────────────────────────────────────────────────
EXT_WS=/opt/ros_external_ws
if [ ! -f "${EXT_WS}/install/setup.bash" ]; then
    echo "--- Building external ROS deps (px4_msgs + workspace extras) ---"
    mkdir -p "${EXT_WS}/src"
    python3 "${SCRIPTS}/generate_ros_repos.py" "${CASE_FILE}" "${REPO_ROOT}" \
        > "${EXT_WS}/preflight.repos"
    vcs import "${EXT_WS}/src" < "${EXT_WS}/preflight.repos"
    (
        cd "${EXT_WS}"
        rosdep update --rosdistro "${ROS_DISTRO}" || true
        rosdep install --from-paths src --ignore-src -r -y --rosdistro "${ROS_DISTRO}"
        colcon build
    )
else
    echo "--- Restored external ROS deps from cache ---"
fi
set +u
# shellcheck disable=SC1090,SC1091
source "${EXT_WS}/install/setup.bash"
set -u

# ──────────────────────────────────────────────────────────────────────────
# Caller workspace: only the packages under test (px4_msgs is the underlay)
# ──────────────────────────────────────────────────────────────────────────
WS=/tmp/ros_ws
rm -rf "${WS}"
mkdir -p "${WS}/src"

# Copy the caller's src/ tree into the workspace. vcs-tool can't ingest a
# local path, so this is the explicit handoff for the package(s) under test.
if [ -d "${REPO_ROOT}/src" ]; then
    # `cp -a` preserves mode bits — important so node scripts marked +x in
    # the caller repo stay +x in the workspace, otherwise ros2 launch will
    # refuse to execute them.
    cp -a "${REPO_ROOT}/src/." "${WS}/src/"
else
    echo "warn: ${REPO_ROOT}/src not found — caller has no ROS packages?" >&2
fi

(
    cd "${WS}"
    rosdep update --rosdistro "${ROS_DISTRO}" || true
    rosdep install --from-paths src --ignore-src -r -y --rosdistro "${ROS_DISTRO}"
    # shellcheck disable=SC2086
    colcon build --symlink-install --packages-up-to ${PACKAGES}
    # shellcheck disable=SC2086
    colcon test --packages-select ${PACKAGES} --event-handlers console_direct+
    # colcon test always exits 0; rely on test-result for the real verdict.
    colcon test-result --verbose
)

mkdir -p /tmp/preflight_output
cp -r "${WS}/log" /tmp/preflight_output/colcon_logs 2>/dev/null || true
