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
load("//python/private/pypi:pep508_evaluate.bzl", "evaluate", "parse", "tokenize")  # buildifier: disable=bzl-visibility

_tests = []

def _check_evaluate(env, expr, expected, values, strict = True):
    env.expect.where(
        expression = expr,
        values = values,
    ).that_bool(evaluate(expr, env = values, strict = strict)).equals(expected)

def _tokenize_tests(env):
    for input, want in {
        "": [],
        "'osx' == os_name": ['"osx"', "==", "os_name"],
        "'x' not in os_name": ['"x"', "not in", "os_name"],
        "('arm' in platform_machine)": ["(", '"arm"', "in", "platform_machine", ")"],
        "()": ["(", ")"],
        "(os_name == 'osx' and os_name != 'posix') or os_name == \"win\"": [
            "(",
            "os_name",
            "==",
            '"osx"',
            "and",
            "os_name",
            "!=",
            '"posix"',
            ")",
            "or",
            "os_name",
            "==",
            '"win"',
        ],
        "os_name\t==\t'osx'": ["os_name", "==", '"osx"'],
        "os_name == \"it's\"": ["os_name", "==", '"it\'s"'],
        "os_name == 'osx'": ["os_name", "==", '"osx"'],
        "platform.version == '#1 SMP (Debian)'": ["platform.version", "==", '"#1 SMP (Debian)"'],
        "python_version <= \"1.0\"": ["python_version", "<=", '"1.0"'],
        "python_version<'3'and(os_name=='nt'or os_name!='nt')": [
            "python_version",
            "<",
            '"3"',
            "and",
            "(",
            "os_name",
            "==",
            '"nt"',
            "or",
            "os_name",
            "!=",
            '"nt"',
            ")",
        ],
        "python_version>='1.0.0'": ["python_version", ">=", '"1.0.0"'],
        "python_version~='1.0.0'": ["python_version", "~=", '"1.0.0"'],
    }.items():
        got = tokenize(input)
        env.expect.that_collection(got).contains_exactly(want).in_order()

_tests.append(_tokenize_tests)

def _evaluate_invalid_tests(env):
    for input in [
        "(",
        ")",
        "()",
        "(())",
        "(os_name == 'posix'",
        "os_name == 'posix')",
        "and os_name == 'posix'",
        "not",
        # The `not` operator is not in the spec.
        "not os_name == 'posix'",
        "not (os_name == 'posix')",
        "os_name == 'posix' and not os_name == 'nt'",
        "os_name",
        "os_name 'posix'",
        "os_name <> 'posix'",
        "os_name = 'posix'",
        "os_name ==",
        "os_name == 'posix",
        "os_name == 'posix\"",
        "os_name == 'posix' and",
        "os_name == 'posix' and and os_name == 'posix'",
        "os_name == 'posix' or or os_name == 'posix'",
        "os_name == 'posix' os_name == 'posix'",
        "os_name == 'posix'\n",
        "os_name == 'po\nsix'",
        "os_name == 'po\rsix'",
        "os_name\r== 'posix'",
        "os_name == posix",
        "'posix' == 'posix'",
        "unknown_variable == 'posix'",
        # The variables that are not in the spec are invalid even if they are in the env.
        "in_env == 'posix'",
    ]:
        got = evaluate(input, env = {"in_env": "posix", "os_name": "posix"}, _fail = lambda _: "invalid")
        env.expect.where(expression = input).that_str(str(got)).equals("invalid")

_tests.append(_evaluate_invalid_tests)

def _evaluate_non_version_env_tests(env):
    for var_name in [
        "implementation_name",
        "os_name",
        "platform_machine",
        "platform_python_implementation",
        "platform_system",
        "platform_version",
        "sys_platform",
        "extra",
    ]:
        # Given
        marker_env = {var_name: "osx"}

        # When
        for input, want in {
            "'osx' != {}".format(var_name): False,
            "'osx' < {}".format(var_name): False,
            "'osx' <= {}".format(var_name): True,
            "'osx' == {}".format(var_name): True,
            "'osx' >= {}".format(var_name): True,
            "'w' not in {}".format(var_name): True,
            "'x' in {}".format(var_name): True,
            "{} != 'osx'".format(var_name): False,
            "{} < 'osx'".format(var_name): False,
            "{} <= 'osx'".format(var_name): True,
            "{} == 'osx'".format(var_name): True,
            "{} > 'osx'".format(var_name): False,
            "{} >= 'osx'".format(var_name): True,
        }.items():
            _check_evaluate(env, input, want, marker_env)

            # Check that the non-strict eval gives us back the input when no
            # env is supplied.
            _check_evaluate(env, input, input.replace("'", '"'), {}, strict = False)

_tests.append(_evaluate_non_version_env_tests)

def _evaluate_version_env_tests(env):
    for var_name in [
        "python_version",
        "implementation_version",
        "platform_release",
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
            "{} == '3.7.*'".format(var_name): True,
            "{} != '3.7.9'".format(var_name): False,
            "{} ~= '3.7.1'".format(var_name): True,
            "{} ~= '3.7.10'".format(var_name): False,
            "{} ~= '3.8.0'".format(var_name): False,
            "{} === '3.7.9+rc2'".format(var_name): False,
            "{} === '3.7.9'".format(var_name): True,
            # The local version of the specifier has to match
            "{} == '3.7.9+rc2'".format(var_name): False,
        }.items():  # buildifier: @unsorted-dict-items
            _check_evaluate(env, input, want, marker_env)

            # Check that the non-strict eval gives us back the input when no
            # env is supplied.
            _check_evaluate(env, input, input.replace("'", '"'), {}, strict = False)

_tests.append(_evaluate_version_env_tests)

def _evaluate_version_as_string_tests(env):
    marker_env = {"python_version": "3.11"}
    for input, want in {
        # The operators that are only defined for strings
        "'3.1' in python_version": True,
        "'3.9' in python_version": False,
        "python_version in '3.10 3.11'": True,
        "python_version not in '3.11'": False,
        "python_version not in '3.9'": True,
        # Not valid version specifiers, so they are compared as strings
        "python_version == 'foo'": False,
        "python_version != 'foo'": True,
        "python_version >= '3.*'": False,
        "python_version >= '3.11+local'": False,
        "python_version < 'foo'": False,
        # Arbitrary equality
        "python_version === '3.11'": True,
        "python_version === '3.11.0'": False,
    }.items():  # buildifier: @unsorted-dict-items
        _check_evaluate(env, input, want, marker_env)

    # Something that is not a version does not match any version specifier.
    for input in [
        "python_version == '3.11'",
        "python_version != '3.11'",
        "python_version >= '3.11'",
    ]:
        _check_evaluate(env, input, False, {"python_version": "foo"})

_tests.append(_evaluate_version_as_string_tests)

def _evaluate_deprecated_names_tests(env):
    marker_env = {
        "os_name": "posix",
        "platform_machine": "x86_64",
        "platform_python_implementation": "CPython",
        "platform_version": "#1 SMP",
        "sys_platform": "linux",
    }
    for input, want in {
        "os.name == 'posix'": True,
        "platform.machine != 'x86_64'": False,
        "platform.python_implementation == 'CPython'": True,
        "platform.version == '#1 SMP'": True,
        "python_implementation == 'CPython'": True,
        "sys.platform == 'linux'": True,
    }.items():
        _check_evaluate(env, input, want, marker_env)

        # The original name is kept when the expression cannot be evaluated.
        _check_evaluate(env, input, input.replace("'", '"'), {}, strict = False)

_tests.append(_evaluate_deprecated_names_tests)

def _evaluate_platform_version_is_a_string(env):
    # Given
    marker_env = {"platform_version": "FooBar Linux v1.2.3"}

    # When the platform version is not a version
    input = "platform_version == '0'"
    _check_evaluate(env, input, False, marker_env)

    # And when I compare it as string
    input = "'FooBar' in platform_version"
    _check_evaluate(env, input, True, marker_env)

    # Check that the non-strict eval gives us back the input when no
    # env is supplied.
    _check_evaluate(env, input, input.replace("'", '"'), {}, strict = False)

_tests.append(_evaluate_platform_version_is_a_string)

def _logical_expression_tests(env):
    for input, want in {
        # Basic
        "": True,

        # expr
        "os_name == 'fo'": False,
        "(os_name == 'fo')": False,
        "((os_name == 'fo'))": False,
        "((os_name == 'foo'))": True,

        # and
        "os_name == 'fo' and os_name == 'foo'": False,

        # or
        "os_name == 'oo' or os_name == 'foo'": True,

        # multiple or
        "os_name == 'oo' or os_name == 'fo' or os_name == 'foo'": True,
        "os_name == 'oo' or os_name == 'foo' or os_name == 'fo'": True,

        # multiple and
        "os_name == 'foo' and os_name == 'foo' and os_name == 'fo'": False,

        # x or y and z != (x or y) and z, but is instead evaluated as x or (y and z)
        "os_name == 'foo' or os_name == 'fo' and os_name == 'fo'": True,

        # x or y and z and w != (x or y and z) and w, but is instead evaluated as x or (y and z and w)
        "os_name == 'foo' or os_name == 'fo' and os_name == 'fo' and os_name == 'fo'": True,
    }.items():  # buildifier: @unsorted-dict-items
        _check_evaluate(env, input, want, {"os_name": "foo"})

        # Check that the non-strict eval gives us back the input when no env
        # is supplied.
        _check_evaluate(env, input, input.replace("'", '"') or True, {}, strict = False)

_tests.append(_logical_expression_tests)

def _evaluate_partial_only_extra(env):
    for input, want in {
        "os_name == 'osx' and extra == 'bar'": False,
        "os_name == 'osx' and extra == 'foo'": "os_name == \"osx\"",
        "platform_system == 'aarch64' and os_name == 'osx' and extra == 'foo'": "platform_system == \"aarch64\" and os_name == \"osx\"",
        "platform_system == 'aarch64' and extra == 'foo' and os_name == 'osx'": "platform_system == \"aarch64\" and os_name == \"osx\"",
        "os_name == 'osx' or extra == 'bar'": "os_name == \"osx\"",
        "os_name == 'osx' or extra == 'foo'": True,
        "extra == 'bar' or os_name == 'osx'": "os_name == \"osx\"",
        "extra == 'foo' or os_name == 'osx'": True,
        "os_name == 'win' or extra == 'bar' or os_name == 'osx'": "os_name == \"win\" or os_name == \"osx\"",
        "os_name == 'win' or extra == 'foo' or os_name == 'osx'": True,
        "(os_name == 'win' or extra == 'foo') and os_name == 'osx'": "os_name == \"osx\"",
        "(os_name == 'win' or extra == 'bar') and os_name == 'osx'": "(os_name == \"win\") and os_name == \"osx\"",
    }.items():  # buildifier: @unsorted-dict-items
        _check_evaluate(env, input, want, {"extra": "foo"}, strict = False)

_tests.append(_evaluate_partial_only_extra)

def _evaluate_with_aliases(env):
    # When
    for (os, cpu), tests in {
        # buildifier: @unsorted-dict-items
        ("osx", "aarch64"): {
            "platform_system == 'Darwin' and platform_machine == 'arm64'": True,
            "platform_system == 'Darwin' and platform_machine == 'aarch64'": True,
            "platform_system == 'Darwin' and platform_machine == 'amd64'": False,
        },
        ("osx", "x86_64"): {
            "platform_system == 'Darwin' and platform_machine == 'amd64'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_64'": True,
        },
        ("osx", "x86_32"): {
            "platform_system == 'Darwin' and platform_machine == 'i386'": True,
            "platform_system == 'Darwin' and platform_machine == 'i686'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_32'": True,
            "platform_system == 'Darwin' and platform_machine == 'x86_64'": False,
        },
        ("freebsd", "x86_32"): {
            "platform_system == 'FreeBSD' and platform_machine == 'i386'": True,
            "platform_system == 'FreeBSD' and platform_machine == 'i686'": True,
            "platform_system == 'FreeBSD' and platform_machine == 'x86_32'": True,
            "platform_system == 'FreeBSD' and platform_machine == 'x86_64'": False,
            "platform_system == 'FreeBSD' and os_name == 'posix'": True,
        },
    }.items():  # buildifier: @unsorted-dict-items
        for input, want in tests.items():
            _check_evaluate(env, input, want, pep508_env(
                os = os,
                arch = cpu,
                python_version = "3.2",
            ))

_tests.append(_evaluate_with_aliases)

def _evaluate_parsed_tests(env):
    marker = parse("python_version >= '3.10' and (sys_platform == 'linux' or extra == 'foo')")
    for values, want in [
        ({"python_version": "3.9", "sys_platform": "linux"}, False),
        ({"python_version": "3.10", "sys_platform": "linux"}, True),
        ({"python_version": "3.11", "sys_platform": "win32"}, "(extra == \"foo\")"),
        ({"extra": "foo", "python_version": "3.11", "sys_platform": "win32"}, True),
        ({"extra": "foo", "sys_platform": "win32"}, "python_version >= \"3.10\""),
    ]:
        got = evaluate(marker, env = values, strict = False)
        env.expect.where(values = values).that_bool(got).equals(want)

_tests.append(_evaluate_parsed_tests)

def _evaluate_partial_roundtrip_tests(env):
    """Evaluating what could not be evaluated must give the same result."""
    full_env = {
        "extra": "foo",
        "os_name": "posix",
        "platform_version": "a \"b\" c",
        "python_version": "3.11",
        "sys_platform": "linux",
    }
    partial_envs = [
        {k: v for k, v in full_env.items() if k not in missing}
        for missing in [
            ["extra"],
            ["os_name", "sys_platform"],
            ["platform_version", "python_version"],
            full_env.keys(),
        ]
    ]
    for marker in [
        "extra == 'foo' or os_name == 'nt'",
        "extra == 'bar' or os_name == 'nt'",
        "(extra == 'foo' or os_name == 'nt') and sys_platform == 'linux'",
        "(extra == 'bar' or os_name == 'posix') and python_version < '3.11'",
        "extra == 'foo' and (os_name == 'nt' or python_version >= '3.8')",
        "(extra != 'foo' and os_name != 'nt') or sys_platform == 'linux'",
        "extra != 'bar' and os_name != 'nt'",
        "platform_version == 'a \"b\" c' and extra == 'foo'",
        "platform_version == \"it's\" or python_version >= '3.8' and os_name == 'posix'",
    ]:
        want = evaluate(marker, env = full_env)
        for partial_env in partial_envs:
            got = evaluate(marker, env = partial_env, strict = False)
            where = env.expect.where(marker = marker, env = partial_env, partial = got)

            # Guard against returning a marker that is always true instead
            # of `True`, which is what we used to do.
            where.that_bool(got in ["", "()"]).equals(False)
            if type(got) == "string":
                got = evaluate(got, env = full_env)
            where.that_bool(got).equals(want)

_tests.append(_evaluate_partial_roundtrip_tests)

def _expr_case(expr, want, env):
    return struct(expr = expr.strip(), want = want, env = env)

_MISC_EXPRESSIONS = [
    _expr_case('python_version == "3.*"', True, {"python_version": "3.10.1"}),
    _expr_case('python_version != "3.10.*"', False, {"python_version": "3.10.1"}),
    _expr_case('python_version != "3.11.*"', True, {"python_version": "3.10.1"}),
    _expr_case('python_version != "3.10"', False, {"python_version": "3.10.0"}),
    _expr_case('python_version == "3.10"', True, {"python_version": "3.10.0"}),
    # Cases for the '>' operator
    # Taken from spec: https://peps.python.org/pep-0440/#exclusive-ordered-comparison
    _expr_case('python_version > "1.7"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version > "1.7"', False, {"python_version": "1.7.0.post0"}),
    _expr_case('python_version > "1.7"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version > "1.7.post2"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version > "1.7.post2"', True, {"python_version": "1.7.post3"}),
    _expr_case('python_version > "1.7.post2"', False, {"python_version": "1.7.0"}),
    _expr_case('python_version > "1.7.1+local"', False, {"python_version": "1.7.1"}),
    # Not a valid version specifier, so it is not compared as a version
    _expr_case('python_version > "1.7.1+local"', False, {"python_version": "1.7.2"}),
    # Extra cases for the '<' operator
    _expr_case('python_version < "1.7.1"', False, {"python_version": "1.7.2"}),
    _expr_case('python_version < "1.7.3"', True, {"python_version": "1.7.2"}),
    _expr_case('python_version < "1.7.1"', True, {"python_version": "1.7"}),
    _expr_case('python_version < "1.7.1"', False, {"python_version": "1.7.1-rc2"}),
    _expr_case('python_version < "1.7.1-rc3"', True, {"python_version": "1.7.1-rc2"}),
    _expr_case('python_version < "1.7.1-rc1"', False, {"python_version": "1.7.1-rc2"}),
    # Extra tests
    _expr_case('python_version <= "1.7.1"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version <= "1.7.2"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version >= "1.7.1"', True, {"python_version": "1.7.1"}),
    _expr_case('python_version >= "1.7.0"', True, {"python_version": "1.7.1"}),
    # Compatible version tests:
    # https://packaging.python.org/en/latest/specifications/version-specifiers/#compatible-release
    _expr_case('python_version ~= "2.2"', True, {"python_version": "2.3"}),
    _expr_case('python_version ~= "2.2"', False, {"python_version": "2.1"}),
    _expr_case('python_version ~= "2.2.0"', True, {"python_version": "2.2"}),
    _expr_case('python_version ~= "2.2.post3"', False, {"python_version": "2.2"}),
    _expr_case('python_version ~= "2.2.post3"', False, {"python_version": "3.0"}),
    _expr_case('python_version ~= "2.2.post3"', True, {"python_version": "2.3"}),
    _expr_case('python_version ~= "1!2.2"', False, {"python_version": "2.7"}),
    _expr_case('python_version ~= "0!2.2"', True, {"python_version": "2.7"}),
    _expr_case('python_version ~= "1!2.2"', True, {"python_version": "1!2.7"}),
    _expr_case('python_version ~= "1.2.3"', True, {"python_version": "1.2.4"}),
    _expr_case('python_version ~= "1.2.3"', False, {"python_version": "1.3.2"}),
]

def _misc_expressions(env):
    for case in _MISC_EXPRESSIONS:
        _check_evaluate(env, case.expr, case.want, case.env)

_tests.append(_misc_expressions)

def evaluate_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
