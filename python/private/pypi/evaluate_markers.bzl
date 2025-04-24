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

"""A simple function that evaluates markers using a python interpreter."""

load(":pep508_env.bzl", "env")
load(":pep508_evaluate.bzl", "evaluate")
load(":pep508_platform.bzl", "platform_from_str")
load(":pep508_requirement.bzl", "requirement")

def evaluate_markers(requirements, python_version = None):
    """Return the list of supported platforms per requirements line.

    Args:
        requirements: {type}`dict[str, list[str]]` of the requirement file lines to evaluate.
        python_version: {type}`str | None` the version that can be used when evaluating the markers.

    Returns:
        dict of string lists with target platforms
    """
    ret = {}
    for req_string, platforms in requirements.items():
        req = requirement(req_string)
        for platform in platforms:
            if evaluate(req.marker, env = env(platform_from_str(platform, python_version))):
                ret.setdefault(req_string, []).append(platform)

    return ret
