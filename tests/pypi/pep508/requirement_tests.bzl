# Copyright 2025 The Bazel Authors. All rights reserved.
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
"""Tests for parsing the requirement specifier."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pep508_requirement.bzl", "requirement")  # buildifier: disable=bzl-visibility

_tests = []

def _test_requirement_line_parsing(env):
    want = {
        " name1[ foo ] ": ("name1", ["foo"], ""),
        "Name[foo]": ("name", ["foo"], ""),
        # No whitespace between the URL and the marker
        "foo @ https://example.org/foo-1.0-py3-none-any.whl; os_name == 'a'": ("foo", [], "os_name == 'a'"),
        "name [fred,bar] @ http://foo.com ; python_version=='2.7'": ("name", ["bar", "fred"], "python_version=='2.7'"),
        "name; (os_name=='a' or os_name=='b') and os_name=='c'": ("name", [], "(os_name=='a' or os_name=='b') and os_name=='c'"),
        "name@http://foo.com": ("name", [], ""),
        "name[ Foo123 ]": ("name", ["foo123"], ""),
        "name[extra-one,extra-two.three]==1.0": ("name", ["extra_one", "extra_two_three"], ""),
        "name[extra]@http://foo.com": ("name", ["extra"], ""),
        "name[foo]": ("name", ["foo"], ""),
        "name[quux, strange];python_version<'2.7' and platform_version=='2'": ("name", ["quux", "strange"], "python_version<'2.7' and platform_version=='2'"),
        "name_foo; platform_release != \"custom -x\"": ("name-foo", [], "platform_release != \"custom -x\""),
        # The text that looks like an option in a quoted marker value is kept
        "name_foo; platform_release != 'custom -- kernel' --hash=sha256:deadbeef": ("name-foo", [], "platform_release != 'custom -- kernel'"),
        "name_foo==0.25\t--hash=sha256:deadbeef": ("name-foo", [], ""),
        # The options may be indented with tabs in the requirements files
        "name_foo==0.25 \t--hash=sha256:deadbeef": ("name-foo", [], ""),
        # The short options, e.g. `-C` for `--config-settings`
        "name_foo==0.25 -Ckey=value --hash=sha256:deadbeef": ("name-foo", [], ""),
        "name_foo==0.25 ; os_name=='a' --hash=sha256:deadbeef": ("name-foo", [], "os_name=='a'"),
        "name_foo[bar]": ("name-foo", ["bar"], ""),
        "name_foo[bar]==0.25": ("name-foo", ["bar"], ""),
        "name_foo[bar]==0.25 --hash=sha256:deadbeef": ("name-foo", ["bar"], ""),
        "name_foo[bar]==0.25 @ http://foo.com ; os_name=='a'": ("name-foo", ["bar"], "os_name=='a'"),
    }

    got = {}
    for case in want:
        parsed = requirement(case)
        got[case] = (parsed.name, parsed.extras, parsed.marker)
    env.expect.that_dict(got).contains_exactly(want)

_tests.append(_test_requirement_line_parsing)

def requirement_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
