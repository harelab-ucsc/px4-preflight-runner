#!/usr/bin/env bash
# Run a "sim" test case end-to-end:
#   1. Ensure PX4-Autopilot is built (delegates to run_px4_build.sh).
#   2. Build (or restore) Micro-XRCE-DDS-Agent.
#   3. Build the caller's ROS workspace with version-matched px4_msgs.
#   4. Inject PX4 param overlay via etc/extras.txt.
#   5. Launch PX4 SITL (SIH), the DDS bridge, and the user's ROS launch
#      file in a coordinated start sequence.
#   6. Record a ros2 bag of all topics for the duration of the test.
#   7. Tear down cleanly, collect ULog + bag artifacts.
#   8. Run any user-provided assertion script and the Hawkeye smoke test.
set -eo pipefail

: "${CASE_FILE:?}"
: "${REPO_ROOT:?}"
: "${SCRIPTS:?}"
: "${PX4_REF:?}"
: "${ROS_DISTRO:?}"
: "${PACKAGES:?}"

# ──────────────────────────────────────────────────────────────────────────
# Read case fields once
# ──────────────────────────────────────────────────────────────────────────
read_field() {
    python3 -c "import json; d=json.load(open('${CASE_FILE}')); v=d.get('$1'); print('' if v is None else v)"
}
read_bool() {
    python3 -c "
import json
d = json.load(open('${CASE_FILE}'))
v = d.get('$1', False)
print('1' if v else '0')
"
}
LAUNCH_FILE=$(read_field launch)
DURATION=$(read_field duration_sec)
ASSERTIONS=$(read_field assertions)
HAWKEYE=$(read_bool hawkeye_replay)
PX4_SIM_MODEL=$(python3 -c "
import json
d = json.load(open('${CASE_FILE}'))
af = d.get('resolved_airframe') or {}
print(af.get('px4_model', 'sihsim_quadx'))
")
DURATION="${DURATION:-60}"
LAUNCH_FILE="${LAUNCH_FILE:-launch/sim.launch.py}"
# `ros2 launch <pkg> <file>` searches share/<pkg>/ by leaf name; it does not
# accept a leading 'launch/' prefix. Strip it so specs can stay readable.
LAUNCH_NAME="${LAUNCH_FILE##*/}"

PX4_DIR="${PX4_DIR:-/tmp/PX4-Autopilot}"
OUTPUT="/tmp/preflight_output"
WS=/tmp/ros_ws
# Wipe stale artifacts so the ULog/rosbag we collect at the end is always
# from THIS run, not a previous one cached in the docker volume.
rm -rf "${OUTPUT}" /root/.ros/log
rm -f /tmp/waypoint_results.json
mkdir -p "${OUTPUT}"

# ──────────────────────────────────────────────────────────────────────────
# Ensure artifacts get uploaded even if the script fails partway through.
# Runs on every exit (success, early failure, or signal) and best-effort:
#   - copies the most recent PX4 ULog into ${OUTPUT}
#   - dumps any /root/.ros/log/* (ros2 launch verbose logs)
#   - dumps a copy of the case JSON for traceability
# ──────────────────────────────────────────────────────────────────────────
collect_artifacts() {
    local rc=$?
    set +e
    if [ -d "${PX4_DIR}/build/px4_sitl_default" ]; then
        local latest
        latest=$(find "${PX4_DIR}/build/px4_sitl_default" \
            -path '*/log/*' -name '*.ulg' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | head -1 | awk '{print $2}')
        if [ -n "${latest}" ] && [ -f "${latest}" ]; then
            cp "${latest}" "${OUTPUT}/" 2>/dev/null || true
        fi
    fi
    if [ -d /root/.ros/log ]; then
        cp -r /root/.ros/log "${OUTPUT}/ros_launch_logs" 2>/dev/null || true
    fi
    [ -f "${CASE_FILE}" ] && cp "${CASE_FILE}" "${OUTPUT}/case.json" 2>/dev/null || true
    if [ -f /tmp/waypoint_results.json ] \
       && [ ! -f "${OUTPUT}/waypoint_results.json" ]; then
        cp /tmp/waypoint_results.json "${OUTPUT}/" 2>/dev/null || true
    fi
    return ${rc}
}
trap collect_artifacts EXIT

# ──────────────────────────────────────────────────────────────────────────
# 1. PX4 build (cached via ccache + the runner's actions/cache step)
# ──────────────────────────────────────────────────────────────────────────
PX4_DIR="${PX4_DIR}" bash "${SCRIPTS}/run_px4_build.sh"

# ──────────────────────────────────────────────────────────────────────────
# 2. Micro-XRCE-DDS Agent
# ──────────────────────────────────────────────────────────────────────────
XRCE_DIR="${XRCE_DIR:-/opt/MicroXRCEAgent}"
XRCE_BIN="${XRCE_DIR}/build/MicroXRCEAgent"
XRCE_REF="${XRCE_REF:-v2.4.3}"
if [ ! -x "${XRCE_BIN}" ]; then
    echo "Building Micro-XRCE-DDS-Agent ${XRCE_REF}"
    if [ ! -d "${XRCE_DIR}" ]; then
        git clone --recursive --branch "${XRCE_REF}" \
            https://github.com/eProsima/Micro-XRCE-DDS-Agent.git \
            "${XRCE_DIR}"
    fi
    (
        cd "${XRCE_DIR}"
        mkdir -p build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release -DUAGENT_BUILD_TESTS=OFF
        make -j"$(nproc)"
    )
fi

# ──────────────────────────────────────────────────────────────────────────
# 3. ROS workspace
# ──────────────────────────────────────────────────────────────────────────
# ROS setup scripts reference unset vars; only enable nounset after sourcing
# (and disable it again before sourcing the workspace overlay later).
# shellcheck disable=SC1090
source "/opt/ros/${ROS_DISTRO}/setup.bash"

rm -rf "${WS}"
mkdir -p "${WS}/src"
if [ -d "${REPO_ROOT}/src" ]; then
    # `cp -a` preserves mode bits; ros2 launch refuses to execute symlinked
    # node scripts that have lost their +x in transit.
    cp -a "${REPO_ROOT}/src/." "${WS}/src/"
fi
python3 "${SCRIPTS}/generate_ros_repos.py" "${CASE_FILE}" "${REPO_ROOT}" \
    > "${WS}/preflight.repos"
vcs import "${WS}/src" < "${WS}/preflight.repos"
(
    cd "${WS}"
    rosdep update --rosdistro "${ROS_DISTRO}" || true
    rosdep install --from-paths src --ignore-src -r -y --rosdistro "${ROS_DISTRO}"
    # shellcheck disable=SC2086
    colcon build --symlink-install --packages-up-to ${PACKAGES}
)

# ──────────────────────────────────────────────────────────────────────────
# 4. PX4 runtime config overlay
# ──────────────────────────────────────────────────────────────────────────
PX4_RUNTIME_DIR="${PX4_DIR}/build/px4_sitl_default"
PX4_ETC="${PX4_RUNTIME_DIR}/etc"
mkdir -p "${PX4_ETC}"

# extras.txt is sourced by PX4's rcS after the airframe loads, which makes
# it the right place to inject param overrides without touching the upstream
# airframe scripts.
EXTRAS="${PX4_ETC}/extras.txt"
python3 "${SCRIPTS}/render_px4_config.py" "${CASE_FILE}" > "${EXTRAS}"
echo "PX4 extras.txt:"
cat "${EXTRAS}" || true

# ──────────────────────────────────────────────────────────────────────────
# 5. Launch PX4 SITL (SIH)
# ──────────────────────────────────────────────────────────────────────────
INSTANCE_DIR="${PX4_RUNTIME_DIR}/instance_0"
mkdir -p "${INSTANCE_DIR}"
cd "${INSTANCE_DIR}"

export PX4_SIM_MODEL="${PX4_SIM_MODEL}"
export PX4_HOME_LAT="${PX4_HOME_LAT:-37.0}"
export PX4_HOME_LON="${PX4_HOME_LON:--122.0}"
export PX4_HOME_ALT="${PX4_HOME_ALT:-30.0}"

PX4_BIN="${PX4_RUNTIME_DIR}/bin/px4"
PX4_LOG="${OUTPUT}/px4_console.log"
echo "Launching PX4: PX4_SIM_MODEL=${PX4_SIM_MODEL}"
"${PX4_BIN}" -d "${PX4_RUNTIME_DIR}/etc" \
    > "${PX4_LOG}" 2>&1 &
PX4_PID=$!
echo "PX4 PID: ${PX4_PID}"

# Wait for PX4 to reach a known-ready state.
echo "Waiting for PX4 to boot..."
for _ in $(seq 1 60); do
    if grep -q "Ready for takeoff" "${PX4_LOG}" 2>/dev/null \
       || grep -q "INFO  \[commander\] Ready" "${PX4_LOG}" 2>/dev/null \
       || grep -q "simulator_sih" "${PX4_LOG}" 2>/dev/null; then
        break
    fi
    sleep 1
done

# ──────────────────────────────────────────────────────────────────────────
# 6. uXRCE-DDS bridge
# ──────────────────────────────────────────────────────────────────────────
"${XRCE_BIN}" udp4 -p 8888 -v 0 \
    > "${OUTPUT}/xrce_agent.log" 2>&1 &
XRCE_PID=$!
sleep 4

# ──────────────────────────────────────────────────────────────────────────
# 7. ros2 bag + user launch
# ──────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC1091
source "${WS}/install/setup.bash"
ros2 bag record -a -s mcap -o "${OUTPUT}/ros_bag" \
    > "${OUTPUT}/rosbag.log" 2>&1 &
BAG_PID=$!
sleep 2

PRIMARY_PKG=$(echo "${PACKAGES}" | awk '{print $1}')
echo "Launching ${PRIMARY_PKG} ${LAUNCH_NAME} for ${DURATION}s"
timeout "${DURATION}s" \
    ros2 launch "${PRIMARY_PKG}" "${LAUNCH_NAME}" \
    > "${OUTPUT}/ros_launch.log" 2>&1 \
    || true

# ──────────────────────────────────────────────────────────────────────────
# 8. Teardown
# ──────────────────────────────────────────────────────────────────────────
kill "${BAG_PID}" 2>/dev/null || true
sleep 3
kill "${PX4_PID}" "${XRCE_PID}" 2>/dev/null || true
wait 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────
# 9. Verify ULog presence (the EXIT trap copied it; we just assert here so
#    a missing log fails the case loudly with the PX4 boot tail in stderr).
# ──────────────────────────────────────────────────────────────────────────
collect_artifacts || true   # eagerly run trap once so ULG is in OUTPUT now
ULG=$(find "${OUTPUT}" -maxdepth 1 -name '*.ulg' | head -1 || true)
if [ -z "${ULG}" ]; then
    echo "FAIL: no .ulg was produced — PX4 may not have booted correctly" >&2
    tail -50 "${PX4_LOG}" >&2 || true
    exit 1
fi
echo "ULog produced: ${ULG} ($(stat -c%s "${ULG}" 2>/dev/null || stat -f%z "${ULG}") bytes)"

# ──────────────────────────────────────────────────────────────────────────
# 10. Assertions (user-provided)
# ──────────────────────────────────────────────────────────────────────────
if [ -n "${ASSERTIONS}" ] && [ -f "${REPO_ROOT}/${ASSERTIONS}" ]; then
    RESULTS=/tmp/waypoint_results.json
    [ -f "${RESULTS}" ] && cp "${RESULTS}" "${OUTPUT}/"
    python3 "${REPO_ROOT}/${ASSERTIONS}" "${OUTPUT}/waypoint_results.json" "${ULG}"
fi

# ──────────────────────────────────────────────────────────────────────────
# 11. Hawkeye replay smoke test
# ──────────────────────────────────────────────────────────────────────────
if [ "${HAWKEYE}" = "1" ]; then
    bash "${SCRIPTS}/hawkeye_smoke_test.sh" "${ULG}"
fi
