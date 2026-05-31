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
load(":parse_sha_manifest_tests.bzl", "parse_sha_manifest_test_suite")
load(":runtime_manifests_tests.bzl", "runtime_manifests_test_suite")

def register_python_bzlmod_ext_tests(name, parse_sha_manifest_name, runtime_manifests_name):
    """Registers the Bzlmod extension tests if Bzlmod is enabled, otherwise defines empty test_suites.

    Args:
        name: The name of the master test_suite target.
        parse_sha_manifest_name: The name of the parse_sha_manifest test target.
        runtime_manifests_name: The name of the runtime_manifests test target.
    """
    if BZLMOD_ENABLED:
        parse_sha_manifest_test_suite(name = parse_sha_manifest_name)
        runtime_manifests_test_suite(name = runtime_manifests_name)
    else:
        native.test_suite(
            name = parse_sha_manifest_name,
            tests = [],
        )
        native.test_suite(
            name = runtime_manifests_name,
            tests = [],
        )

    native.test_suite(
        name = name,
        tests = [
            parse_sha_manifest_name,
            runtime_manifests_name,
        ],
    )
