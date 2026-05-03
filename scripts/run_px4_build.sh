#!/usr/bin/env bash
# Clone PX4-Autopilot at the requested tag and build the SITL binary.
# Output binary: ${PX4_DIR}/build/px4_sitl_default/bin/px4
#
# This script is shared between the "px4_build" case type and the "sim" case
# type. It is idempotent: if PX4_DIR already contains a built binary, it
# skips the rebuild.
set -eo pipefail

: "${PX4_REF:?}"

PX4_DIR="${PX4_DIR:-/tmp/PX4-Autopilot}"
PX4_BIN="${PX4_DIR}/build/px4_sitl_default/bin/px4"

if [ -x "${PX4_BIN}" ]; then
    echo "PX4 already built at ${PX4_BIN}"
else
    if [ ! -d "${PX4_DIR}" ]; then
        echo "Cloning PX4-Autopilot @ ${PX4_REF}"
        git clone --depth 1 --branch "${PX4_REF}" --recurse-submodules \
            https://github.com/PX4/PX4-Autopilot.git "${PX4_DIR}"
    fi

    (
        cd "${PX4_DIR}"
        # px4_sitl_default builds the binary without launching it. The
        # downstream run step is responsible for picking the airframe via
        # PX4_SIM_MODEL.
        make px4_sitl_default
    )
    if command -v ccache >/dev/null; then
        ccache -s || true
    fi
fi

mkdir -p /tmp/preflight_output
# Only the px4_build case type uploads the binary itself — sim cases would
# add 50 MB of bloat to every artifact for no debug value.
if [ "${PUBLISH_PX4_BIN:-0}" = "1" ]; then
    cp "${PX4_BIN}" /tmp/preflight_output/px4_bin || true
fi
