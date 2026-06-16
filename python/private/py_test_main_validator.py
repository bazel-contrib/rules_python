# Copyright 2024 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Static check that a py_test main module actually runs something.

A common ``py_test`` pitfall is to define test classes or functions but forget
to add any code that actually executes them (for example, assuming that
``py_test`` automatically invokes ``unittest`` or ``pytest``). When that
happens, running the test does nothing and the target silently passes.

This validator parses the main module with :mod:`ast` and fails if the
module body is "inert", i.e. every top-level statement is one that does not
run anything (definitions, imports, assignments, docstrings, ``pass``). A
single active statement -- a bare call, a loop, or the conventional
``if __name__ == "__main__":`` guard -- is enough to consider the module able
to run tests.

As an exception, a module that defines no classes or functions at all (for
example, one that only imports other modules) is always allowed: it isn't the
"defined some tests but forgot to run them" case this check targets, and it
may legitimately rely on import side effects.
"""

import argparse
import ast
import sys

# Statement node types that do not, on their own, run any test code. A module
# whose top-level body consists solely of these is considered inert.
_INERT_NODE_TYPES = [
    ast.FunctionDef,
    ast.AsyncFunctionDef,
    ast.ClassDef,
    ast.Import,
    ast.ImportFrom,
    ast.Assign,
    ast.AnnAssign,
    ast.AugAssign,
    ast.Global,
    ast.Pass,
]

# `ast.TypeAlias` (PEP 695, e.g. `type Alias = int`) only exists on Python
# 3.12+. Add it dynamically so the validator still imports on older versions.
if hasattr(ast, "TypeAlias"):
    _INERT_NODE_TYPES.append(ast.TypeAlias)

_INERT_NODE_TYPES = tuple(_INERT_NODE_TYPES)


def _is_inert_statement(node: ast.stmt) -> bool:
    """Returns True if the top-level statement does not run any test code."""
    if isinstance(node, _INERT_NODE_TYPES):
        return True

    # Bare constant expressions: docstrings, `...` (Ellipsis), and similar
    # no-op expression statements.
    if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant):
        return True

    return False


def module_runs_something(tree: ast.Module) -> bool:
    """Returns True if the module body has at least one active statement."""
    return any(not _is_inert_statement(node) for node in tree.body)


def _defines_test_code(tree: ast.Module) -> bool:
    """Returns True if the module defines any top-level class or function."""
    return any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
        for node in tree.body
    )


def module_runs_tests(tree: ast.Module) -> bool:
    """Returns True if the module appears able to run tests (or isn't checked).

    The check targets the specific pitfall of defining test classes/functions
    but never running them. A module that defines no classes or functions at
    all (for example, one that only imports other modules) is not subject to
    the check and is always allowed, since it isn't the "defined but never run"
    case and may legitimately rely on import side effects.
    """
    if module_runs_something(tree):
        return True
    return not _defines_test_code(tree)


def _format_error(label: str, src_name: str) -> str:
    target = label or src_name
    return (
        "py_test target {target} will not run any tests.\n"
        "\n"
        "The main module '{src_name}' only contains inert top-level statements "
        "(class/function definitions, imports, assignments). Running it does "
        "nothing, so the test silently passes without executing any test "
        "code.\n"
        "\n"
        "py_test runs the main module directly; it does not automatically "
        "invoke a test runner such as unittest or pytest. Add code that runs "
        "your tests, for example:\n"
        "\n"
        '    if __name__ == "__main__":\n'
        "        unittest.main()\n"
        "\n"
        "or use a main module that invokes a runner (e.g. pytest.main()).\n"
        "\n"
        "This check can be disabled by setting "
        "--@rules_python//python/config_settings:validate_test_main=disabled."
    ).format(target=target, src_name=src_name)


def main(args) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--src",
        required=True,
        help="Path to the main .py source file to analyze.",
    )
    parser.add_argument(
        "--src_name",
        default="",
        help="Human-friendly name of the source file, used in error messages.",
    )
    parser.add_argument(
        "--label",
        default="",
        help="The py_test target label, used in error messages.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to the validation marker file to write on success.",
    )
    options = parser.parse_args(args)

    src_name = options.src_name or options.src

    with open(options.src, "rb") as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=src_name)
    except SyntaxError as e:
        # A syntax error is surfaced by other actions (compilation/execution).
        # The validator can't analyze the file, so don't fail here; treat it as
        # passing to avoid duplicate or confusing errors.
        sys.stderr.write(
            "WARNING: py_test main validator could not parse {}: {}\n".format(
                src_name, e
            )
        )
        with open(options.output, "w") as out:
            out.write("")
        return 0

    if not module_runs_tests(tree):
        sys.stderr.write(_format_error(options.label, src_name) + "\n")
        return 1

    # Validation actions must produce their declared outputs on success.
    with open(options.output, "w") as out:
        out.write("")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
