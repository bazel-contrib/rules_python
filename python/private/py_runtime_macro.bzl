# Copyright 2022 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Macro to wrap the py_runtime rule."""

load(":common_labels.bzl", "labels")
load(
    ":py_runtime_rule.bzl",
    "coverage_tool_target",
    py_runtime_rule = "py_runtime",
)

# NOTE: The function name is purposefully selected to match the underlying
# rule name so that e.g. 'generator_function' shows as the same name so
# that it is less confusing to users.
def py_runtime(*, name, coverage_tool = None, **kwargs):
    """Wraps the py_runtime rule.

    The `coverage_tool` is dropped when building the coverage tool itself, so
    that it can depend on the Python toolchain, e.g. a `py_library` from a pip
    hub. Otherwise, it would be a dependency cycle.

    Args:
        name: {type}`str` the name of the target.
        coverage_tool: {type}`Label | select | None` the coverage tool.
        **kwargs: forwarded to the rule.
    """
    if coverage_tool != None:
        # Compose caller `select()` expressions with the bootstrap guard via a
        # helper target. `native.alias` cannot be used because `alias.actual` is
        # mandatory (rejecting `select()` branches resolving to `None`) and
        # would evaluate caller `select()` conditions after the coverage_tool
        # transition disables `collect_code_coverage`.
        coverage_tool_alias = "_{}_coverage_tool".format(name)
        coverage_tool_target(
            name = coverage_tool_alias,
            actual = coverage_tool,
            tags = ["manual"],
            visibility = ["//visibility:private"],
        )
        coverage_tool = select({
            labels.IS_BOOTSTRAP_RUNTIME_FALSE: ":" + coverage_tool_alias,
            "//conditions:default": None,
        })

    py_runtime_rule(
        name = name,
        coverage_tool = coverage_tool,
        **kwargs
    )
