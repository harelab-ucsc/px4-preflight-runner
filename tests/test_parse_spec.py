"""Unit tests for parse_spec.py, resolve_px4_msgs_ref.py, render_px4_config.py."""

import json
import os
import subprocess
import sys
import textwrap

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir))
SCRIPTS = os.path.join(ROOT, "scripts")
sys.path.insert(0, SCRIPTS)

import parse_spec  # noqa: E402
import render_px4_config  # noqa: E402
import resolve_px4_msgs_ref  # noqa: E402


def _spec(text):
    import yaml
    return yaml.safe_load(textwrap.dedent(text))


def test_minimal_spec_emits_matrix():
    spec = _spec(
        """
        version: 1
        defaults:
          ros_distro: humble
          px4_ref: v1.16.0
        tests:
          - name: ros-only
            type: ros_unit
            packages: [demo_pkg]
        """
    )
    matrix = parse_spec.build_matrix(spec)
    assert "include" in matrix
    assert len(matrix["include"]) == 1
    case = matrix["include"][0]
    assert case["name"] == "ros-only"
    assert case["type"] == "ros_unit"
    assert case["ros_distro"] == "humble"
    assert case["px4_ref"] == "v1.16.0"
    assert case["resolved_airframe"] is None


def test_extends_chain_resolves():
    spec = _spec(
        """
        airframes:
          base:
            vehicle: iris
            params: {A: 1, B: 2}
          tuned:
            extends: base
            params: {B: 99, C: 3}
        environments:
          sih: {container_image: img}
        tests:
          - name: t
            type: sim
            airframe: tuned
            environment: sih
        """
    )
    matrix = parse_spec.build_matrix(spec)
    af = matrix["include"][0]["resolved_airframe"]
    assert af["vehicle"] == "iris"
    assert af["params"] == {"A": 1, "B": 99, "C": 3}


def test_circular_extends_raises():
    spec = _spec(
        """
        airframes:
          a: {extends: b}
          b: {extends: a}
        tests:
          - {name: t, type: sim, airframe: a}
        """
    )
    with pytest.raises(parse_spec.SpecError, match="circular"):
        parse_spec.build_matrix(spec)


def test_variable_substitution():
    spec = _spec(
        """
        defaults:
          ros_distro: humble
        environments:
          e:
            container_image: "px4io/px4-dev-ros2-${ros_distro}:latest"
        tests:
          - {name: t, type: ros_unit, environment: e}
        """
    )
    case = parse_spec.build_matrix(spec)["include"][0]
    assert case["container_image"] == "px4io/px4-dev-ros2-humble:latest"


def test_missing_environment_raises():
    spec = _spec(
        """
        tests:
          - {name: t, type: ros_unit, environment: nope}
        """
    )
    with pytest.raises(parse_spec.SpecError, match="environment 'nope'"):
        parse_spec.build_matrix(spec)


def test_missing_airframe_raises():
    spec = _spec(
        """
        airframes:
          base: {vehicle: iris}
        tests:
          - {name: t, type: sim, airframe: ghost}
        """
    )
    with pytest.raises(parse_spec.SpecError, match="airframe 'ghost'"):
        parse_spec.build_matrix(spec)


def test_invalid_type_raises():
    spec = _spec(
        """
        tests:
          - {name: t, type: nonsense}
        """
    )
    with pytest.raises(parse_spec.SpecError, match="must be one of"):
        parse_spec.build_matrix(spec)


def test_empty_tests_raises():
    spec = _spec("tests: []")
    with pytest.raises(parse_spec.SpecError, match="non-empty 'tests'"):
        parse_spec.build_matrix(spec)


def test_resolve_px4_msgs_ref():
    assert resolve_px4_msgs_ref.resolve("v1.16.0") == "release/1.16"
    assert resolve_px4_msgs_ref.resolve("v1.14.3") == "release/1.14"
    assert resolve_px4_msgs_ref.resolve("main") == "main"
    assert resolve_px4_msgs_ref.resolve("garbage") == "main"


def test_render_px4_config():
    case = {
        "resolved_airframe": {
            "params": {"MIS_TAKEOFF_ALT": 5.0, "COM_RC_IN_MODE": 1},
        }
    }
    out = render_px4_config.render(case)
    assert "param set MIS_TAKEOFF_ALT 5.0" in out
    assert "param set COM_RC_IN_MODE 1" in out


def test_render_px4_config_no_airframe():
    assert render_px4_config.render({"resolved_airframe": None}) == ""
    assert render_px4_config.render({}) == ""


def test_parse_spec_cli(tmp_path):
    spec_file = tmp_path / "spec.yaml"
    spec_file.write_text(
        textwrap.dedent(
            """
            tests:
              - {name: t, type: ros_unit}
            """
        )
    )
    result = subprocess.run(
        [sys.executable, os.path.join(SCRIPTS, "parse_spec.py"), str(spec_file)],
        capture_output=True, text=True, check=True,
    )
    matrix = json.loads(result.stdout)
    assert matrix["include"][0]["name"] == "t"


def test_parse_spec_cli_bad_input(tmp_path):
    spec_file = tmp_path / "spec.yaml"
    spec_file.write_text("tests: [{name: x, type: invalid_type}]")
    result = subprocess.run(
        [sys.executable, os.path.join(SCRIPTS, "parse_spec.py"), str(spec_file)],
        capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "must be one of" in result.stderr
