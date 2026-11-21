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
* The partial evaluation, which is used to evaluate what is known when the
  repositories are created (e.g. the `extra`) and to leave the rest for the
  analysis phase.
"""

load("@pypackaging.bzl", "pypackaging")

_AND = "and"
_OR = "or"

_PLATFORM_MACHINE_ALIASES = {
    # These pairs mean the same hardware, but different values may be used
    # on different host platforms.
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86_32",
    "i686": "x86_32",
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

    # Each frame is the list that is being reduced, the index of the next
    # item in it and the values of the items that have been reduced so far.
    stack = [(tree, 0, [])]

    # Each step advances an index or pops a frame, so this always terminates.
    for _ in range(2 * len(marker) + 2):
        items, i, values = stack[-1]

        if i >= len(items):
            value = _reduce(values)
            stack.pop()
            if not stack:
                if type(value) == "bool":
                    return value
                return pypackaging.markers.to_string([value])

            stack[-1][2].append(value)
            continue

        item = items[i]
        stack[-1] = (items, i + 1, values)

        if type(item) == "list":
            stack.append((item, 0, []))
        elif type(item) == "tuple":
            values.append(_evaluate_item(item, env = env, strict = strict))
        else:
            values.append(item)

    return fail("BUG: failed to evaluate the marker: {}".format(marker))

def _evaluate_item(item, *, env, strict):
    """Evaluate a single `<left> <op> <right>` expression.

    Returns:
        {type}`bool` or the item itself if it uses a variable that is not in
        the env and `strict` is `False`.
    """
    lhs, op, rhs = item

    if not strict:
        for side in (lhs, rhs):
            if side.type == "variable" and side.value not in env:
                return item

    if lhs.type == "variable" and lhs.value == "platform_machine":
        rhs = _platform_machine(rhs)
    elif rhs.type == "variable" and rhs.value == "platform_machine":
        lhs = _platform_machine(lhs)

    return pypackaging.markers.evaluate([(lhs, op, rhs)], env)

def _platform_machine(value):
    if value.type != "string":
        return value

    return struct(
        type = value.type,
        value = _PLATFORM_MACHINE_ALIASES.get(value.value, value.value),
    )

def _reduce(values):
    """Reduce the values of a single (parenthesized) expression.

    Args:
        values: {type}`list` the values separated by the `and` and `or`
            operators. A value is a {type}`bool`, an expression that could
            not be evaluated or a list of such for a parenthesized expression.

    Returns:
        {type}`bool` or a list for what could not be evaluated.
    """

    # `and` binds tighter than `or`, so do the `and` groups first
    groups = [[]]
    for value in values:
        if value == _OR:
            groups.append([])
        elif value != _AND:
            groups[-1].append(value)

    remaining = []
    for group in groups:
        if False in group:
            continue

        group = [v for v in group if v != True]
        if not group:
            return True

        if remaining:
            remaining.append(_OR)

        for i, value in enumerate(group):
            if i:
                remaining.append(_AND)
            remaining.append(value)

    if not remaining:
        return False

    if len(remaining) == 1:
        # No need to keep the parentheses.
        return remaining[0]

    return remaining
