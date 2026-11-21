"""Generate Starlark conformance test cases from the `pypa/packaging` project.

The test inputs are harvested from the `packaging` test-suite and the expected
values are computed with (or taken from) the very same `packaging` release, so
that the Starlark implementations are compared with the reference
implementation of the PyPA specifications.

Update the checked-in files with:

    bazel run //tests/support/pypa_packaging:update
"""

import argparse
import ast
import itertools
import json
import operator
import os
import pathlib
import random
import sys
import types
import typing

import packaging
from packaging.markers import InvalidMarker, Marker, UndefinedComparison
from packaging.specifiers import InvalidSpecifier, Specifier

_HEADER = '''"""Conformance test cases generated from `packaging=={version}`.

GENERATED FILE, DO NOT EDIT. Update with:

    bazel run //tests/support/pypa_packaging:update
"""
'''

_VERSION_OPERATORS = ["==", "!=", "<", "<=", ">", ">=", "~="]

# Versions used to exercise every operator against every specifier below. The
# packaging test-suite has examples for each operator, but this gives us an
# exhaustive table for the edge cases: zero padding, pre/post/dev releases,
# local versions and epochs.
_MATRIX_VERSIONS = [
    "3",
    "3.0",
    "3.0.0",
    "3.0.1",
    "3.1",
    "3.9",
    "3.10",
    "3.10.0",
    "3.10.1",
    "3.13.dev1",
    "3.13.0.dev1",
    "3.13.0a1.dev1",
    "3.13.0a1",
    "3.13.0a1.post2",
    "3.13.0a2",
    "3.13.0b1",
    "3.13.0rc1.dev1",
    "3.13.0rc1",
    "3.13rc2",
    "3.13",
    "3.13.0",
    "3.13.0+local",
    "3.13.0+local.2",
    "3.13.0+3",
    "3.13.post1.dev2",
    "3.13.post1",
    "3.13.0.post1",
    "3.13.0.post1+local",
    "3.13.0.post2",
    "3.13.1.dev0",
    "3.13.1",
    "3.14",
    "4.dev0",
    "4",
    "1!3.0",
    "1!3.13",
]

# The `.*` suffix is only valid with the `==` and `!=` operators and the local
# versions cannot be used with the ordered comparisons, the invalid
# combinations are skipped.
_MATRIX_SPECS = _MATRIX_VERSIONS + [
    "3.*",
    "3.0.*",
    "3.1.*",
    "3.10.*",
    "3.13.*",
    "3.13.0.*",
    "1!3.*",
]


# The environment that is used to evaluate the markers, unless the test case
# overrides the values.
_MARKER_ENV = {
    "extra": "foo",
    "implementation_name": "cpython",
    "implementation_version": "3.11.4",
    "os_name": "posix",
    "platform_machine": "x86_64",
    "platform_python_implementation": "CPython",
    "platform_release": "6.1.0",
    "platform_system": "Linux",
    "platform_version": "#1 SMP PREEMPT_DYNAMIC Debian 6.1.55-1 (2023-09-29)",
    "python_full_version": "3.11.4",
    "python_version": "3.11",
    "sys_platform": "linux",
}

# The variables that are sets, their value in the environment and the values
# to test the membership of.
_SET_VARIABLES = ["extras", "dependency_groups"]
_SET_ENV_VALUE = ["foo", "bar-baz"]
_SET_VALUES = ["foo", "Foo", "fo", "bar-baz", "Bar_Baz", "bar.baz", "bar", ""]

# The expressions that are combined with `and`, `or` and parenthesis to test
# the precedence and the grouping.
_MARKER_ATOMS = [
    'os_name == "posix"',
    'os_name == "nt"',
    "sys_platform != 'linux'",
    'python_version >= "3.8"',
    'python_full_version < "3.11.4"',
    'platform_machine in "x86_64 amd64"',
    '"arm" in platform_machine',
    '"posix" == os_name',
    'extra == "foo"',
]


def _pytest_stub():
    """A minimal stand-in so that the test modules do not need pytest."""
    return types.SimpleNamespace(param=lambda *args, **kwargs: args)


class _TestModule:
    """Extracts constants and `pytest.mark.parametrize` values of a test file."""

    def __init__(self, path, **namespace):
        self._tree = ast.parse(pathlib.Path(path).read_text(encoding="utf-8"))
        self.namespace: dict[str, typing.Any] = {
            "itertools": itertools,
            "operator": operator,
            "os": os,
            "pytest": _pytest_stub(),
        }
        self.namespace.update(namespace)

        # Only the upper case constants are evaluated, they are used by the
        # parametrize expressions.
        for node in self._tree.body:
            if (
                isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id.isupper()
            ):
                try:
                    self.namespace[node.targets[0].id] = self._eval(node.value)
                except NameError:
                    # Depends on helpers of the test module, not needed.
                    pass

    def _eval(self, node):
        code = compile(ast.Expression(node), "<packaging tests>", "eval")
        return eval(code, self.namespace)  # pylint: disable=eval-used

    def parametrize(self, test_name):
        """Returns the values of the parametrize decorator of the given test."""
        for node in ast.walk(self._tree):
            if not isinstance(node, ast.FunctionDef) or node.name != test_name:
                continue
            for decorator in node.decorator_list:
                if (
                    isinstance(decorator, ast.Call)
                    and ast.unparse(decorator.func) == "pytest.mark.parametrize"
                ):
                    return list(self._eval(decorator.args[1]))
        raise ValueError("no parametrized test named: " + test_name)


def _split_specifier(spec):
    for op in ["===", "==", "!=", "~=", "<=", ">=", "<", ">"]:
        if spec.startswith(op):
            return op, spec[len(op) :].strip()
    raise ValueError("unknown operator in: " + spec)


def _str(value):
    return json.dumps(value, ensure_ascii=False)


def _list(name, values, comment):
    lines = ["", "# " + comment, name + " = ["]
    for value in values:
        if isinstance(value, tuple):
            items = [_str(v) if isinstance(v, str) else repr(v) for v in value]
            lines.append("    ({}),".format(", ".join(items)))
        else:
            lines.append("    {},".format(_str(value)))
    lines.append("]")
    return "\n".join(lines) + "\n"


def _matrix():
    rows = []
    for op in _VERSION_OPERATORS:
        for spec in _MATRIX_SPECS:
            try:
                specifier = Specifier(op + spec)
            except InvalidSpecifier:
                continue
            row = "".join(
                [
                    "T" if specifier.contains(v, prereleases=True) else "F"
                    for v in _MATRIX_VERSIONS
                ]
            )
            rows.append((op, spec, row))
    return rows


def version_cases(test_version, test_specifiers):
    """Generate the test cases for `//python/private:version.bzl`."""
    versions = _TestModule(test_version)
    specifiers = _TestModule(test_specifiers, VERSIONS=versions.namespace["VERSIONS"])

    specifier_cases = []
    for candidate, spec, expected in specifiers.parametrize("test_specifiers"):
        op, spec_version = _split_specifier(spec)
        specifier_cases.append((candidate, op, spec_version, expected))

    return "".join(
        [
            _HEADER.format(version=packaging.__version__),
            _list(
                "ORDERED_VERSIONS",
                versions.namespace["VERSIONS"],
                "Valid versions in the ascending order.",
            ),
            _list(
                "INVALID_VERSIONS",
                versions.parametrize("test_invalid_versions"),
                "Strings that are not valid versions.",
            ),
            _list(
                "NORMALIZED_VERSIONS",
                [
                    (version, normalized)
                    for version, normalized in versions.parametrize(
                        "test_normalized_versions"
                    )
                    # Starlark strings are not unicode aware, so the unicode
                    # whitespace is not supported.
                    if version.isascii()
                ],
                "(version, normalized)",
            ),
            _list(
                "SPECIFIER_CASES",
                specifier_cases,
                "(version, operator, specifier version, expected)",
            ),
            _list(
                "MATRIX_VERSIONS",
                _MATRIX_VERSIONS,
                "The versions that the columns of MATRIX correspond to.",
            ),
            _list(
                "MATRIX",
                _matrix(),
                "(operator, specifier version, T/F for each of MATRIX_VERSIONS)",
            ),
        ]
    )


def _evaluate_marker(marker, env):
    try:
        return Marker(marker).evaluate(env)
    except (InvalidMarker, UndefinedComparison):
        return None


def _random_marker(rng, depth):
    if depth == 0 or rng.random() < 0.3:
        return rng.choice(_MARKER_ATOMS)

    marker = _random_marker(rng, depth - 1)
    for _ in range(rng.randint(1, 3)):
        marker += rng.choice([" and ", " or "]) + _random_marker(rng, depth - 1)

    return "({})".format(marker) if rng.random() < 0.5 else marker


def _marker_table(env, variables, operators, values):
    rows = []
    for variable, op, value in itertools.product(variables, operators, values):
        # The test builds the markers the same way.
        assert '"' not in value, value
        result = ""
        for marker in [
            '{} {} "{}"'.format(variable, op, value),
            '"{}" {} {}'.format(value, op, variable),
        ]:
            got = _evaluate_marker(marker, env)
            # "E" means that it is an error to evaluate the marker.
            result += "E" if got is None else "T" if got else "F"
        rows.append((variable, op, value, result))
    return rows


def marker_cases(test_markers):
    """Generate the test cases for `//python/private/pypi:pep508_evaluate.bzl`."""
    markers = _TestModule(test_markers)

    evaluate_cases = []
    for test_name in [
        "test_evaluates",
        "test_evaluate_pep345_markers",
        "test_version_like_equality",
    ]:
        for marker, env, expected in markers.parametrize(test_name):
            if env is None:
                # These depend on the interpreter that runs the tests.
                continue

            got = _evaluate_marker(marker, _MARKER_ENV | env)
            if got != expected:
                raise ValueError(
                    "The default environment changes the result of: " + marker
                )
            evaluate_cases.append((marker, json.dumps(env, sort_keys=True), expected))

    invalid = markers.parametrize("test_parses_invalid") + [
        'python_version >= "3"' + line_break
        for line_break in markers.parametrize("test_parses_invalid_trailing_line_break")
    ]

    rng = random.Random(508)
    logic = {}
    for _ in range(100):
        marker = _random_marker(rng, 3)
        logic[marker] = _evaluate_marker(marker, _MARKER_ENV)

    ns = markers.namespace
    return "".join(
        [
            _HEADER.format(version=packaging.__version__),
            _list(
                "MARKER_ENV",
                sorted(_MARKER_ENV.items()),
                "The (name, value) of the default environment for the cases below.",
            ),
            _list(
                "EVALUATE_CASES",
                evaluate_cases,
                "(marker, JSON of the environment overrides, expected)",
            ),
            _list(
                "INVALID_MARKERS",
                invalid,
                "Strings that are not valid markers.",
            ),
            _list(
                "MARKER_TABLE",
                _marker_table(
                    _MARKER_ENV,
                    ns["VARIABLES"]
                    + ns["PEP_345_VARIABLES"]
                    + ns["SETUPTOOLS_VARIABLES"],
                    ns["OPERATORS"],
                    ns["VALUES"],
                ),
                "(variable, operator, value, results); the results are T/F/E(rror) for\n"
                "# `<variable> <operator> <value>` and `<value> <operator> <variable>`.",
            ),
            _list(
                "SET_ENV_VALUE",
                _SET_ENV_VALUE,
                "The value of the variables that are sets for the cases below.",
            ),
            _list(
                "SET_TABLE",
                _marker_table(
                    _MARKER_ENV
                    | {v: frozenset(_SET_ENV_VALUE) for v in _SET_VARIABLES},
                    _SET_VARIABLES,
                    ["in", "not in"],
                    _SET_VALUES,
                ),
                "The same as the `MARKER_TABLE`, but for the variables that are sets.",
            ),
            _list(
                "LOGIC_CASES",
                sorted(logic.items()),
                "(marker, expected)",
            ),
        ]
    )


def _resolve(path):
    """Resolve a path that may be a runfiles path."""
    if os.path.exists(path):
        return path

    from python.runfiles import runfiles

    rfiles = runfiles.Create()
    assert rfiles is not None, "Failed to create runfiles"
    resolved = rfiles.Rlocation(path)
    if not resolved or not os.path.exists(resolved):
        raise FileNotFoundError(path)
    return resolved


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-version", required=True)
    parser.add_argument("--test-specifiers", required=True)
    parser.add_argument("--test-markers", required=True)
    parser.add_argument(
        "--version-cases",
        required=True,
        help="The file with the version test cases to write or check.",
    )
    parser.add_argument(
        "--marker-cases",
        required=True,
        help="The file with the marker test cases to write or check.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the files are out of date instead of writing them.",
    )
    args = parser.parse_args(argv)

    outputs = {
        args.version_cases: version_cases(
            _resolve(args.test_version),
            _resolve(args.test_specifiers),
        ),
        args.marker_cases: marker_cases(_resolve(args.test_markers)),
    }

    stale = []
    for path, content in outputs.items():
        if args.check:
            current = pathlib.Path(_resolve(path)).read_text(encoding="utf-8")
            if current != content:
                stale.append(path)
            continue

        root = os.environ.get("BUILD_WORKSPACE_DIRECTORY", "")
        out = pathlib.Path(root, path)
        out.write_text(content, encoding="utf-8")
        print("Wrote", out)

    if stale:
        print(
            "Out of date: {}\nRun: bazel run //tests/support/pypa_packaging:update".format(
                ", ".join(stale),
            ),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
