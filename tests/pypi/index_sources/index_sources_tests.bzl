# Copyright 2023 The Bazel Authors. All rights reserved.
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

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:index_sources.bzl", "index_sources")  # buildifier: disable=bzl-visibility

_tests = []

def _test_no_simple_api_sources(env):
    inputs = {
        "foo @ git+https://github.com/org/foo.git@deadbeef": struct(
            requirement = "foo @ git+https://github.com/org/foo.git@deadbeef",
            marker = "",
            url = "git+https://github.com/org/foo.git@deadbeef",
            shas = [],
            version = "",
        ),
        "foo==0.0.1": struct(
            requirement = "foo==0.0.1",
            marker = "",
            url = "",
            version = "0.0.1",
        ),
        "foo==0.0.1 @ https://someurl.org": struct(
            requirement = "foo==0.0.1 @ https://someurl.org",
            marker = "",
            url = "https://someurl.org",
            version = "0.0.1",
        ),
        "foo==0.0.1 @ https://someurl.org/package.whl": struct(
            requirement = "foo==0.0.1 @ https://someurl.org/package.whl",
            marker = "",
            url = "https://someurl.org/package.whl",
            version = "0.0.1",
        ),
        "foo==0.0.1 @ https://someurl.org/package.whl --hash=sha256:deadbeef": struct(
            requirement = "foo==0.0.1 @ https://someurl.org/package.whl --hash=sha256:deadbeef",
            marker = "",
            url = "https://someurl.org/package.whl",
            shas = ["deadbeef"],
            version = "0.0.1",
        ),
        "foo==0.0.1 @ https://someurl.org/package.whl; python_version < \"2.7\"\\    --hash=sha256:deadbeef": struct(
            requirement = "foo==0.0.1 @ https://someurl.org/package.whl --hash=sha256:deadbeef",
            marker = "python_version < \"2.7\"",
            url = "https://someurl.org/package.whl",
            shas = ["deadbeef"],
            version = "0.0.1",
        ),
    }
    for input, want in inputs.items():
        got = index_sources(input)
        env.expect.that_collection(got.shas).contains_exactly(want.shas if hasattr(want, "shas") else [])
        env.expect.that_str(got.version).equals(want.version)
        env.expect.that_str(got.requirement).equals(want.requirement)
        env.expect.that_str(got.requirement_line).equals(got.requirement)
        env.expect.that_str(got.marker).equals(want.marker)
        env.expect.that_str(got.url).equals(want.url)

_tests.append(_test_no_simple_api_sources)

def _test_simple_api_sources(env):
    tests = {
        "foo==0.0.2 --hash=sha256:deafbeef    --hash=sha256:deadbeef": struct(
            shas = [
                "deadbeef",
                "deafbeef",
            ],
            marker = "",
            requirement = "foo==0.0.2",
            requirement_line = "foo==0.0.2 --hash=sha256:deafbeef --hash=sha256:deadbeef",
            url = "",
        ),
        "foo[extra]==0.0.2; (python_version < 2.7 or extra == \"@\") --hash=sha256:deafbeef    --hash=sha256:deadbeef": struct(
            shas = [
                "deadbeef",
                "deafbeef",
            ],
            marker = "(python_version < 2.7 or extra == \"@\")",
            requirement = "foo[extra]==0.0.2",
            requirement_line = "foo[extra]==0.0.2 --hash=sha256:deafbeef --hash=sha256:deadbeef",
            url = "",
        ),
    }
    for input, want in tests.items():
        got = index_sources(input)
        env.expect.that_collection(got.shas).contains_exactly(want.shas)
        env.expect.that_str(got.version).equals("0.0.2")
        env.expect.that_str(got.requirement).equals(want.requirement)
        env.expect.that_str(got.requirement_line).equals(want.requirement_line)
        env.expect.that_str(got.marker).equals(want.marker)
        env.expect.that_str(got.url).equals(want.url)

_tests.append(_test_simple_api_sources)

def index_sources_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
