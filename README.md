# px4-preflight-runner

Reusable GitHub Actions composite actions, container image, and orchestration
scripts for running PX4 + ROS 2 offboard tests in CI. The runner is
deliberately thin: it parses a declarative spec (`.preflight/spec.yaml`) from
the caller repo, fans the resulting matrix out, and executes each case.

## Layout

| Path | Purpose |
|---|---|
| `actions/parse-spec/` | Composite action: caller spec → matrix JSON |
| `actions/run-case/` | Composite action: one matrix entry → one job |
| `scripts/` | Python + bash backing the composite actions |
| `docker/` | Dockerfile for the prebuilt runner image |
| `testdata/minimal_pkg/` | Self-test fixture: a minimal ROS package + spec |
| `tests/` | Unit tests for the Python scripts |

## Usage from a caller repo

```yaml
jobs:
  generate-matrix:
    runs-on: ubuntu-22.04
    outputs:
      matrix: ${{ steps.parse.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - id: parse
        uses: harelab-ucsc/px4-preflight-runner/actions/parse-spec@main

  run-case:
    needs: generate-matrix
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}
    runs-on: ubuntu-22.04
    container:
      image: ${{ matrix.container_image }}
      options: --privileged --user root
    steps:
      - uses: actions/checkout@v4
      - uses: harelab-ucsc/px4-preflight-runner/actions/run-case@main
        with:
          case-json: ${{ toJson(matrix) }}
```

See `testdata/minimal_pkg/.preflight/spec.yaml` for the smallest valid spec.

## Self-tests

Layer 1 (static): `pytest tests/`, shellcheck, yamllint, actionlint.
Layer 2 (parser fixture): the action processes the bundled `minimal_pkg` spec.
Layer 3 (ROS): runs `colcon build` + `colcon test` on `minimal_pkg` against a
version-matched `px4_msgs`.
Layer 4 (sim, planned): runs PX4 SIH + uXRCE-DDS + a ROS launch end-to-end.
Layer 5 (negative): verifies bad specs fail loudly.

## Container image

The runner ships a prebuilt image at
`ghcr.io/harelab-ucsc/px4-preflight-runner:<ros_distro>` with colcon, vcs,
rosdep, and the runner's Python deps already installed. Build locally with:

```bash
docker build -f docker/Dockerfile -t px4-preflight-runner:humble .
```
