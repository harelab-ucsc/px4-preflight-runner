#!/usr/bin/env python3
"""Read .preflight/spec.yaml and emit a GitHub Actions matrix JSON string.

The spec describes test cases that the px4-preflight-runner should execute.
Each test references an environment (container + env vars) and optionally an
airframe (PX4 model + parameter overlay). This script flattens that into a
single matrix entry per test, ready for GitHub Actions strategy.matrix.
"""

import copy
import json
import re
import sys

import yaml


VAR_PATTERN = re.compile(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}")
VALID_TYPES = {"ros_unit", "px4_build", "sim"}


class SpecError(ValueError):
    pass


def deep_merge(base, override):
    result = copy.deepcopy(base)
    for k, v in override.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v)
        else:
            result[k] = copy.deepcopy(v)
    return result


def resolve_extends(airframes, name, seen=None):
    seen = seen or set()
    if name not in airframes:
        raise SpecError(f"airframe '{name}' is not defined")
    if name in seen:
        chain = " -> ".join(list(seen) + [name])
        raise SpecError(f"circular extends in airframes: {chain}")
    seen = seen | {name}
    frame = copy.deepcopy(airframes[name])
    parent_name = frame.pop("extends", None)
    if parent_name:
        parent = resolve_extends(airframes, parent_name, seen)
        return deep_merge(parent, frame)
    return frame


def substitute_vars(obj, variables):
    if isinstance(obj, str):
        def repl(m):
            key = m.group(1)
            if key not in variables:
                return m.group(0)
            return str(variables[key])
        return VAR_PATTERN.sub(repl, obj)
    if isinstance(obj, dict):
        return {k: substitute_vars(v, variables) for k, v in obj.items()}
    if isinstance(obj, list):
        return [substitute_vars(i, variables) for i in obj]
    return obj


def validate_test(test, environments, airframes):
    if "name" not in test:
        raise SpecError("each test must have a 'name'")
    name = test["name"]
    if "type" not in test:
        raise SpecError(f"test '{name}': missing 'type'")
    if test["type"] not in VALID_TYPES:
        raise SpecError(
            f"test '{name}': type '{test['type']}' must be one of {sorted(VALID_TYPES)}"
        )
    env = test.get("environment")
    if env is not None and env not in environments:
        raise SpecError(f"test '{name}': environment '{env}' is not defined")
    af = test.get("airframe")
    if af is not None and af not in airframes:
        raise SpecError(f"test '{name}': airframe '{af}' is not defined")


def build_matrix(spec):
    if not isinstance(spec, dict):
        raise SpecError("spec must be a mapping at the top level")
    if "tests" not in spec or not isinstance(spec["tests"], list) or not spec["tests"]:
        raise SpecError("spec must define a non-empty 'tests' list")

    defaults = spec.get("defaults", {}) or {}
    airframes = spec.get("airframes", {}) or {}
    environments = spec.get("environments", {}) or {}
    ros_workspace_extra = spec.get("ros_workspace_extra", {}) or {}

    matrix = []
    for test in spec["tests"]:
        validate_test(test, environments, airframes)

        case = copy.deepcopy(defaults)

        env_name = test.get("environment")
        if env_name:
            case = deep_merge(case, environments[env_name])

        airframe_name = test.get("airframe")
        if airframe_name:
            case["resolved_airframe"] = resolve_extends(airframes, airframe_name)
        else:
            case["resolved_airframe"] = None

        case = deep_merge(case, test)
        case["ros_workspace_extra"] = ros_workspace_extra

        case = substitute_vars(case, defaults)
        matrix.append(case)

    return {"include": matrix}


def main(argv):
    if len(argv) != 2:
        print("usage: parse_spec.py <spec.yaml>", file=sys.stderr)
        return 2
    path = argv[1]
    try:
        with open(path) as f:
            spec = yaml.safe_load(f)
        matrix = build_matrix(spec)
    except (SpecError, yaml.YAMLError, FileNotFoundError) as e:
        print(f"parse_spec: {e}", file=sys.stderr)
        return 1
    print(json.dumps(matrix))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
