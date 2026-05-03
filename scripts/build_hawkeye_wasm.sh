#!/usr/bin/env bash
# Build Hawkeye's WASM artifacts at a pinned commit and copy them into
# the requested output dir.
#
# Usage:
#   build_hawkeye_wasm.sh <output_dir>
#
# Env (optional):
#   HAWKEYE_REF   commit SHA (or branch/tag) to check out (default: pinned below)
#   HAWKEYE_DIR   working dir for the clone (default: /tmp/Hawkeye)
#
# The Hawkeye WASM build is moving fast; we pin a known-good SHA rather
# than tracking `main` so a breaking upstream change cannot break our PRs.
# Bump this when we want to consume a newer Hawkeye release.
set -euo pipefail

# Pinned Hawkeye commit (refresh after upstream releases & local smoke test).
HAWKEYE_PIN="${HAWKEYE_REF:-e8f191ce40a6516595e4c607f793f125a0aeafae}"
HAWKEYE_DIR="${HAWKEYE_DIR:-/tmp/Hawkeye}"

OUTPUT="${1:?usage: build_hawkeye_wasm.sh <output_dir>}"
mkdir -p "${OUTPUT}"

# Sanity-check toolchain. Caller is expected to have `emcmake` on PATH —
# we don't install emsdk here because that's a multi-hundred-MB pull and
# belongs in a dedicated job step (or container image).
if ! command -v emcmake >/dev/null 2>&1; then
    echo "build_hawkeye_wasm: emcmake not on PATH — source emsdk_env.sh first" >&2
    exit 1
fi

if [ ! -d "${HAWKEYE_DIR}" ]; then
    git clone https://github.com/PX4/Hawkeye.git "${HAWKEYE_DIR}"
fi
git -C "${HAWKEYE_DIR}" fetch --depth 1 origin "${HAWKEYE_PIN}" 2>/dev/null \
    || git -C "${HAWKEYE_DIR}" fetch
git -C "${HAWKEYE_DIR}" checkout "${HAWKEYE_PIN}"

(
    cd "${HAWKEYE_DIR}"
    emcmake cmake -S wasm -B wasm/build -DCMAKE_BUILD_TYPE=Release
    cmake --build wasm/build -j"$(nproc)"
)

# Required artifacts — fail loudly if any are missing.
for f in hawkeye.js hawkeye.wasm index.html; do
    if [ ! -f "${HAWKEYE_DIR}/wasm/build/${f}" ]; then
        echo "build_hawkeye_wasm: expected artifact ${f} not produced" >&2
        exit 1
    fi
    cp "${HAWKEYE_DIR}/wasm/build/${f}" "${OUTPUT}/"
done

# .data is optional (only emitted once asset preloading is wired upstream).
if [ -f "${HAWKEYE_DIR}/wasm/build/hawkeye.data" ]; then
    cp "${HAWKEYE_DIR}/wasm/build/hawkeye.data" "${OUTPUT}/"
fi

# Record the pinned commit so the bundle is self-describing.
git -C "${HAWKEYE_DIR}" rev-parse HEAD > "${OUTPUT}/hawkeye_commit.txt"

echo "build_hawkeye_wasm: wrote artifacts to ${OUTPUT}"
ls -la "${OUTPUT}"
