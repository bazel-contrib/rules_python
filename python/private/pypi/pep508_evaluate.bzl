# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Evaluate the PEP 508 environment markers.

The parsing and the evaluation is done by `pypackaging.bzl`, this module adds
what `rules_python` needs on top of it:

* The `platform_machine` aliases, so that e.g. `arm64` and `aarch64` mean the
  same thing.
* A single function for the full and the partial evaluation. The latter is
  used to evaluate what is known when the repositories are created (e.g. the
  `extra`) and to leave the rest for the analysis phase.
"""

load("@bazel_skylib//lib:types.bzl", "types")
load("@pypackaging.bzl", "pypackaging")

# These pairs mean the same hardware, but different values may be used on
# different host platforms.
_PLATFORM_MACHINE_ALIASES = {
    # keep-sorted start
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
    # keep-sorted end
}

def evaluate(marker, *, env, strict = True):
    """Evaluate the marker against a given env.

    Args:
        marker: {type}`str` The string marker to evaluate.
        env: {type}`dict[str, str]` The environment to evaluate the marker against.
        strict: {type}`bool` A setting to not fail on missing values in the env.

    Returns:
        The {type}`bool | str` If the marker is compatible with the given env. If strict is
        `False`, then the output type is `str` if a part of the marker could
        not be evaluated and it will represent the remaining expression.
    """
    tree = pypackaging.markers.parse(marker)
    if "platform_machine" in marker and "platform_machine" in env:
        # The comparisons that are not evaluated are left as they are written.
        tree = _with_platform_machine_aliases(tree, max_depth = len(marker))

        # The value in the env may be an alias as well.
        machine = env["platform_machine"]
        env = env | {
            "platform_machine": _PLATFORM_MACHINE_ALIASES.get(machine, machine),
        }

    if strict:
        return pypackaging.markers.evaluate(tree, env)

    result = pypackaging.markers.evaluate_partial(tree, env)
    if types.is_bool(result):
        return result

    return pypackaging.markers.to_string(result)

def _with_platform_machine_aliases(tree, *, max_depth):
    """Use the canonical names in the comparisons with `platform_machine`.

    Args:
        tree: {type}`list` the parsed marker.
        max_depth: {type}`int` the upper bound for the number of the
            parenthesized expressions in the marker.

    Returns:
        {type}`list` a copy of the parsed marker.
    """
    result = []

    # The pairs of the list to copy and the list to copy it to.
    todo = [(tree, result)]
    for _ in range(max_depth + 1):
        if not todo:
            break

        src, dst = todo.pop()
        for item in src:
            if types.is_list(item):
                nested = []
                dst.append(nested)
                todo.append((item, nested))
            elif types.is_tuple(item):
                dst.append(_with_platform_machine_alias(item))
            else:
                dst.append(item)

    return result

def _with_platform_machine_alias(item):
    lhs, op, rhs = item
    if lhs.type == "variable" and lhs.value == "platform_machine":
        return (lhs, op, _platform_machine(rhs))
    elif rhs.type == "variable" and rhs.value == "platform_machine":
        return (_platform_machine(lhs), op, rhs)
    else:
        return item

def _platform_machine(value):
    if value.type != "string":
        return value

    return struct(
        type = value.type,
        value = _PLATFORM_MACHINE_ALIASES.get(value.value, value.value),
    )
