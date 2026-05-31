# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Helpers to conditionally register tests depending on Bzlmod enablement."""

load("//python/private:bzlmod_enabled.bzl", "BZLMOD_ENABLED")  # buildifier: disable=bzl-visibility
load(":python_tests.bzl", "python_test_suite")

def register_python_tests(name):
    """Registers the python tests if Bzlmod is enabled, otherwise defines an empty test_suite.

    Args:
        name: The name of the test target.
    """
    if BZLMOD_ENABLED:
        python_test_suite(name = name)
    else:
        native.test_suite(
            name = name,
            tests = [],
        )
