#!/usr/bin/env bash
# Dispatcher for a single matrix case. Reads CASE_JSON from the env, parses
# out the type/name/version fields, exports them, then hands off to one of
# run_ros_unit.sh / run_px4_build.sh / run_sim.sh.
set -euo pipefail

: "${CASE_JSON:?CASE_JSON env var is required}"
: "${REPO_ROOT:?REPO_ROOT env var is required}"
: "${ACTION_ROOT:?ACTION_ROOT env var is required}"

SCRIPTS="${ACTION_ROOT}/../../scripts"

# Persist the case to disk so child scripts can re-read it without shell
# quoting hassles.
CASE_FILE="${CASE_FILE:-/tmp/preflight_case.json}"
printf '%s' "${CASE_JSON}" > "${CASE_FILE}"

read_case() {
    python3 -c "import json,sys; d=json.load(open('${CASE_FILE}')); print(d.get('$1', '$2'))"
}

TYPE=$(read_case type "")
NAME=$(read_case name "unnamed")
PX4_REF=$(read_case px4_ref "v1.16.0")
ROS_DISTRO=$(read_case ros_distro "humble")
PACKAGES=$(python3 -c "import json; print(' '.join(json.load(open('${CASE_FILE}')).get('packages', [])))")

export CASE_FILE TYPE NAME PX4_REF ROS_DISTRO PACKAGES SCRIPTS

mkdir -p /tmp/preflight_output

echo "::group::Case: ${NAME} (${TYPE})"

case "${TYPE}" in
    ros_unit)
        bash "${SCRIPTS}/run_ros_unit.sh"
        ;;
    px4_build)
        # Only this case type publishes the px4 binary as an artifact.
        PUBLISH_PX4_BIN=1 bash "${SCRIPTS}/run_px4_build.sh"
        ;;
    sim)
        bash "${SCRIPTS}/run_sim.sh"
        ;;
    *)
        echo "Unknown test type: ${TYPE}" >&2
        exit 1
        ;;
esac

echo "::endgroup::"
