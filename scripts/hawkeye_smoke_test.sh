#!/usr/bin/env bash
# Hawkeye replay smoke test.
#
# Hawkeye is a GUI replay tool (Raylib + MAVLink). Two-part smoke check:
#   1. pyulog can parse the .ulg — proves PX4 produced a coherent log.
#   2. If hawkeye is installable on this runner and Xvfb is available, run
#      `hawkeye --replay` under a virtual display with a kill-after timeout.
#      This catches obvious replay-time crashes without requiring a window.
#
# The script never hard-fails on Hawkeye install/runtime issues — those are
# environmental — but does fail loudly if pyulog rejects the log.
set -eo pipefail
ULG="${1:?usage: hawkeye_smoke_test.sh <ulg_path>}"

if [ ! -s "${ULG}" ]; then
    echo "hawkeye-smoke: ULog missing or empty: ${ULG}" >&2
    exit 1
fi

echo "hawkeye-smoke: validating ${ULG} with pyulog"
python3 - <<PY
import sys
from pyulog import ULog

ulg = ULog("${ULG}")
datasets = {d.name for d in ulg.data_list}
required = {"vehicle_status", "vehicle_local_position"}
missing = required - datasets
if missing:
    print(f"FAIL: ULog is missing topics: {sorted(missing)}", file=sys.stderr)
    sys.exit(1)
print(f"OK: ULog parsed cleanly with {len(datasets)} topics")
PY

# ── Optional GUI replay under Xvfb ──────────────────────────────────────
install_hawkeye() {
    if command -v hawkeye >/dev/null 2>&1; then
        return 0
    fi
    if [ "$(uname -m)" != "x86_64" ]; then
        echo "hawkeye-smoke: skipping GUI replay (non-x86_64 host)" >&2
        return 1
    fi
    TAG=$(curl -sf https://api.github.com/repos/PX4/Hawkeye/releases/latest \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])") || return 1
    VERSION="${TAG#v}"
    URL="https://github.com/PX4/Hawkeye/releases/download/${TAG}/hawkeye_${VERSION}_amd64.deb"
    if ! curl -fLso /tmp/hawkeye.deb "${URL}"; then
        echo "hawkeye-smoke: failed to download ${URL}, skipping" >&2
        return 1
    fi
    if ! sudo dpkg -i /tmp/hawkeye.deb >/dev/null 2>&1; then
        sudo apt-get install -y --no-install-recommends -f >/dev/null 2>&1 || true
        sudo dpkg -i /tmp/hawkeye.deb >/dev/null 2>&1 || return 1
    fi
}

if ! install_hawkeye; then
    echo "hawkeye-smoke: install failed, skipping GUI replay (ULog parse already passed)"
    exit 0
fi

if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "hawkeye-smoke: xvfb-run not present, skipping GUI replay"
    exit 0
fi

echo "hawkeye-smoke: launching hawkeye --replay under xvfb-run (5s)"
# Hawkeye has no native duration flag, so wrap with `timeout`. Exit code 124
# from `timeout` is the expected "we killed it" path; treat anything else
# (segfault, missing libs, immediate exit > 0) as a failure.
set +e
xvfb-run -a -s "-screen 0 1280x720x24" \
    timeout --signal=SIGTERM --preserve-status 5 hawkeye --replay "${ULG}"
status=$?
set -e
case "${status}" in
    124|143)
        echo "hawkeye-smoke: replay ran for the full 5s window (status=${status})"
        ;;
    0)
        echo "hawkeye-smoke: hawkeye exited 0 (file replay finished early)"
        ;;
    *)
        echo "hawkeye-smoke: hawkeye exited ${status} during replay" >&2
        exit 1
        ;;
esac
