# px4-preflight-runner base image.
#
# Bakes in everything the runner's composite actions need so that test cases
# do not pay a fresh apt-get / pip install on every job. The image is built
# and pushed by .github/workflows/release.yml; the demo workflow references
# it as `ghcr.io/harelab-ucsc/px4-preflight-runner:humble`.
#
# Layers:
#   - ros:humble base (provides rclpy, ament_*, colcon, vcs, rosdep, cmake)
#   - apt deps for building PX4-Autopilot and uXRCE-DDS Agent
#   - python deps used by runner scripts (pyyaml, pyulog, jinja2)
#   - rosdep init/update so that `rosdep install` works offline-friendly
ARG ROS_DISTRO=humble
FROM ros:${ROS_DISTRO}

ARG ROS_DISTRO
ENV ROS_DISTRO=${ROS_DISTRO} \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# System deps. Kept in one RUN so the layer stays small.
# Three groups:
#   - generic build/runtime tooling
#   - ROS 2 packages used by the runner self-test fixture and demo
#   - PX4 SITL build deps (genromfs, python helpers, xmllint, etc.)
#   - Headless GUI deps (xvfb) used for the Hawkeye replay smoke test
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git wget gnupg sudo \
        build-essential ccache cmake ninja-build pkg-config \
        python3-pip python3-venv python3-dev \
        python3-colcon-common-extensions \
        python3-vcstool python3-rosdep python3-rosinstall-generator \
        python3-empy python3-jinja2 python3-numpy python3-toml \
        python3-future python3-pyparsing python3-yaml \
        ros-${ROS_DISTRO}-ament-cmake-pytest \
        ros-${ROS_DISTRO}-ament-lint-auto \
        ros-${ROS_DISTRO}-ament-lint-common \
        ros-${ROS_DISTRO}-launch \
        ros-${ROS_DISTRO}-launch-ros \
        ros-${ROS_DISTRO}-rclpy \
        ros-${ROS_DISTRO}-rosbag2-storage-mcap \
        libtinyxml2-dev libasio-dev libxml2-utils \
        genromfs gperf rsync unzip zip \
        xvfb \
 && rm -rf /var/lib/apt/lists/*

# Python deps. Two groups:
#   - Runner scripts: pyyaml, pyulog, jinja2, pytest.
#   - PX4 cmake configure + build: kconfiglib (menuconfig), pyros-genmsg,
#     pymavlink, packaging, jsonschema, cerberus, lxml, future, sympy,
#     pyserial, toml, nunavut, psutil, packaging — taken from PX4's
#     Tools/setup/requirements.txt, narrowed to what px4_sitl_default
#     actually pulls in at configure/build time.
RUN pip install --no-cache-dir \
        pyyaml pyulog jinja2 pytest \
        kconfiglib pyros-genmsg pymavlink \
        cerberus jsonschema lxml future sympy \
        pyserial toml nunavut psutil packaging \
        empy==3.3.4

# Initialize rosdep so `rosdep install` works at runtime. Tolerate failure
# if the source list is already initialized in the base image.
RUN (rosdep init 2>/dev/null || true) \
 && su -c "rosdep update --rosdistro=${ROS_DISTRO}" root

WORKDIR /workspace
