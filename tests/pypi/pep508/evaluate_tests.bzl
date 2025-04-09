# Copyright 2024 The Bazel Authors. All rights reserved.
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
"""Tests for construction of Python version matching config settings."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "tokenize")  # buildifier: disable=bzl-visibility

_tests = []

def _tokenize_tests(env):
    for input, want in {
        "": [],
        "'osx' == os_name": ['"osx"', "==", "os_name"],
        "'x' not in os_name": ['"x"', "not in", "os_name"],
        "()": ["(", ")"],
        "(os_name == 'osx' and not os_name == 'posix') or os_name == \"win\"": [
            "(",
            "os_name",
            "==",
            '"osx"',
            "and",
            "not",
            "os_name",
            "==",
            '"posix"',
            ")",
            "or",
            "os_name",
            "==",
            '"win"',
        ],
        "os_name\t==\t'osx'": ["os_name", "==", '"osx"'],
        "os_name == 'osx'": ["os_name", "==", '"osx"'],
        "python_version <= \"1.0\"": ["python_version", "<=", '"1.0"'],
        "python_version>='1.0.0'": ["python_version", ">=", '"1.0.0"'],
        "python_version~='1.0.0'": ["python_version", "~=", '"1.0.0"'],
    }.items():
        got = tokenize(input)
        env.expect.that_collection(got).contains_exactly(want).in_order()

_tests.append(_tokenize_tests)

def _evaluate_non_version_env_tests(env):
    for var_name in [
        "implementation_name",
        "os_name",
        "platform_machine",
        "platform_python_implementation",
        "platform_release",
        "platform_system",
        "sys_platform",
        "extra",
    ]:
        # Given
        marker_env = {var_name: "osx"}

        # When
        for input, want in {
            "{} == 'osx'".format(var_name): True,
            "{} != 'osx'".format(var_name): False,
            "'osx' == {}".format(var_name): True,
            "'osx' != {}".format(var_name): False,
            "'x' in {}".format(var_name): True,
            "'w' not in {}".format(var_name): True,
        }.items():  # buildifier: @unsorted-dict-items
            got = evaluate(
                input,
                env = marker_env,
            )
            env.expect.that_bool(got).equals(want)

            # Check that the non-strict eval gives us back the input when no
            # env is supplied.
            got = evaluate(
                input,
                env = {},
                strict = False,
            )
            env.expect.that_bool(got).equals(input.replace("'", '"'))

_tests.append(_evaluate_non_version_env_tests)

def _evaluate_version_env_tests(env):
    for var_name in [
        "python_version",
        "implementation_version",
        "platform_version",
        "python_full_version",
    ]:
        # Given
        marker_env = {var_name: "3.7.9"}

        # When
        for input, want in {
            "{} < '3.8'".format(var_name): True,
            "{} > '3.7'".format(var_name): True,
            "{} >= '3.7.9'".format(var_name): True,
            "{} >= '3.7.10'".format(var_name): False,
            "{} >= '3.7.8'".format(var_name): True,
            "{} <= '3.7.9'".format(var_name): True,
            "{} <= '3.7.10'".format(var_name): True,
            "{} <= '3.7.8'".format(var_name): False,
            "{} == '3.7.9'".format(var_name): True,
            "{} != '3.7.9'".format(var_name): False,
            "{} ~= '3.7.1'".format(var_name): True,
            "{} ~= '3.7.10'".format(var_name): False,
            "{} ~= '3.8.0'".format(var_name): False,
            "{} === '3.7.9+rc2'".format(var_name): False,
            "{} === '3.7.9'".format(var_name): True,
            "{} == '3.7.9+rc2'".format(var_name): True,
        }.items():  # buildifier: @unsorted-dict-items
            got = evaluate(
                input,
                env = marker_env,
            )
            env.expect.that_collection((input, got)).contains_exactly((input, want))

            # Check that the non-strict eval gives us back the input when no
            # env is supplied.
            got = evaluate(
                input,
                env = {},
                strict = False,
            )
            env.expect.that_bool(got).equals(input.replace("'", '"'))

_tests.append(_evaluate_version_env_tests)

def _logical_expression_tests(env):
    for input, want in {
        # Basic
        "": True,
        "(())": True,
        "()": True,

        # expr
        "os_name == 'fo'": False,
        "(os_name == 'fo')": False,
        "((os_name == 'fo'))": False,
        "((os_name == 'foo'))": True,
        "not (os_name == 'fo')": True,

        # and
        "os_name == 'fo' and os_name == 'foo'": False,

        # and not
        "os_name == 'fo' and not os_name == 'foo'": False,

        # or
        "os_name == 'oo' or os_name == 'foo'": True,

        # or not
        "os_name == 'foo' or not os_name == 'foo'": True,

        # multiple or
        "os_name == 'oo' or os_name == 'fo' or os_name == 'foo'": True,
        "os_name == 'oo' or os_name == 'foo' or os_name == 'fo'": True,

        # multiple and
        "os_name == 'foo' and os_name == 'foo' and os_name == 'fo'": False,

        # x or not y and z != (x or not y), but is instead evaluated as x or (not y and z)
        "os_name == 'foo' or not os_name == 'fo' and os_name == 'fo'": True,

        # x or y and z != (x or y) and z, but is instead evaluated as x or (y and z)
        "os_name == 'foo' or os_name == 'fo' and os_name == 'fo'": True,
        "not (os_name == 'foo' or os_name == 'fo' and os_name == 'fo')": False,

        # x or y and z and w != (x or y and z) and w, but is instead evaluated as x or (y and z and w)
        "os_name == 'foo' or os_name == 'fo' and os_name == 'fo' and os_name == 'fo'": True,

        # not not True
        "not not os_name == 'foo'": True,
        "not not not os_name == 'foo'": False,
    }.items():  # buildifier: @unsorted-dict-items
        got = evaluate(
            input,
            env = {
                "os_name": "foo",
            },
        )
        env.expect.that_collection((input, got)).contains_exactly((input, want))

        if not input.strip("()"):
            # These cases will just return True, because they will be evaluated
            # and the brackets will be processed.
            continue

        # Check that the non-strict eval gives us back the input when no env
        # is supplied.
        got = evaluate(
            input,
            env = {},
            strict = False,
        )
        env.expect.that_bool(got).equals(input.replace("'", '"'))

_tests.append(_logical_expression_tests)

def _evaluate_partial_only_extra(env):
    # Given
    extra = "foo"

    # When
    for input, want in {
        "os_name == 'osx' and extra == 'bar'": False,
        "os_name == 'osx' and extra == 'foo'": "os_name == \"osx\"",
        "platform_system == 'aarch64' and os_name == 'osx' and extra == 'foo'": "platform_system == \"aarch64\" and os_name == \"osx\"",
        "platform_system == 'aarch64' and extra == 'foo' and os_name == 'osx'": "platform_system == \"aarch64\" and os_name == \"osx\"",
        "os_name == 'osx' or extra == 'bar'": "os_name == \"osx\"",
        "os_name == 'osx' or extra == 'foo'": "",
        "extra == 'bar' or os_name == 'osx'": "os_name == \"osx\"",
        "extra == 'foo' or os_name == 'osx'": "",
        "os_name == 'win' or extra == 'bar' or os_name == 'osx'": "os_name == \"win\" or os_name == \"osx\"",
        "os_name == 'win' or extra == 'foo' or os_name == 'osx'": "",
    }.items():  # buildifier: @unsorted-dict-items
        got = evaluate(
            input,
            env = {
                "extra": extra,
            },
            strict = False,
        )
        env.expect.that_bool(got).equals(want)

_tests.append(_evaluate_partial_only_extra)

def _evaluate_with_aliases(env):
    # When
    for target_platform, tests in {
        # buildifier: @unsorted-dict-items
        "osx_aarch64": {
            "platform_system == 'Darwin' and platform_machine == 'arm64'": True,
            "platform_system == 'Darwin' and platform_machine == 'aarch64'": True,
            "platform_system == 'Darwin' and platform_machine == 'amd64'": False,
        },
        "osx_x86_64": {
            "platform_system == 'Darwin' and platform_machine == 'amd64'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_64'": True,
        },
        "osx_x86_32": {
            "platform_system == 'Darwin' and platform_machine == 'i386'": True,
            "platform_system == 'Darwin' and platform_machine == 'i686'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_32'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_64'": False,
        },
    }.items():  # buildifier: @unsorted-dict-items
        for input, want in tests.items():
            got = evaluate(
                input,
                env = pep508_env(target_platform),
            )
            env.expect.that_bool(got).equals(want)

_tests.append(_evaluate_with_aliases)

def evaluate_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
