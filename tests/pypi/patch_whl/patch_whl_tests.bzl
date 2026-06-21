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

""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:patch_whl.bzl", "fix_record_content", "patched_whl_name")  # buildifier: disable=bzl-visibility

_tests = []

def _test_simple(env):
    got = patched_whl_name("foo-1.2.3-py3-none-any.whl")
    env.expect.that_str(got).equals("foo-1.2.3+patched-py3-none-any.whl")

_tests.append(_test_simple)

def _test_simple_local_version(env):
    got = patched_whl_name("foo-1.2.3+special-py3-none-any.whl")
    env.expect.that_str(got).equals("foo-1.2.3+special.patched-py3-none-any.whl")

_tests.append(_test_simple_local_version)

def _test_fix_record_adds_missing(env):
    record = """\
foo/__init__.py,sha256=abc,123
foo-1.0.dist-info/RECORD,,
"""
    all_files = {
        "foo-1.0.dist-info/METADATA": True,
        "foo-1.0.dist-info/RECORD": True,
        "foo/__init__.py": True,
        "foo/bar.py": True,
    }
    result = fix_record_content(
        record_content = record,
        all_files = all_files,
        record_rel = "foo-1.0.dist-info/RECORD",
    )
    env.expect.that_str(result).contains("foo/bar.py,sha256=0,0")
    env.expect.that_str(result).contains("foo-1.0.dist-info/METADATA,sha256=0,0")

_tests.append(_test_fix_record_adds_missing)

def _test_fix_record_no_missing(env):
    record = """\
foo/__init__.py,sha256=abc,123
foo/bar.py,sha256=def,456
foo-1.0.dist-info/RECORD,,
"""
    all_files = {
        "foo-1.0.dist-info/RECORD": True,
        "foo/__init__.py": True,
        "foo/bar.py": True,
    }
    result = fix_record_content(
        record_content = record,
        all_files = all_files,
        record_rel = "foo-1.0.dist-info/RECORD",
    )
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_fix_record_no_missing)

def _test_fix_record_preserves_quoting(env):
    record = '''\
"foo/__init__.py",sha256=abc,123
"foo-1.0.dist-info/RECORD",,
'''
    all_files = {
        "foo-1.0.dist-info/RECORD": True,
        "foo/__init__.py": True,
        "foo/bar.py": True,
    }
    result = fix_record_content(
        record_content = record,
        all_files = all_files,
        record_rel = "foo-1.0.dist-info/RECORD",
    )
    env.expect.that_str(result).contains('"foo/bar.py",sha256=0,0')

_tests.append(_test_fix_record_preserves_quoting)

def _test_fix_record_skips_excluded(env):
    record = """\
foo/__init__.py,sha256=abc,123
foo-1.0.dist-info/RECORD,,
"""
    all_files = {
        "foo-1.0.dist-info/INSTALLER": True,
        "foo-1.0.dist-info/RECORD": True,
        "foo/__init__.py": True,
    }
    result = fix_record_content(
        record_content = record,
        all_files = all_files,
        record_rel = "foo-1.0.dist-info/RECORD",
    )
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_fix_record_skips_excluded)

def _test_fix_record_skips_whl_files(env):
    record = """\
foo/__init__.py,sha256=abc,123
foo-1.0.dist-info/RECORD,,
"""
    all_files = {
        "foo-1.0.dist-info/RECORD": True,
        "foo-1.0.whl": True,
        "foo/__init__.py": True,
    }
    result = fix_record_content(
        record_content = record,
        all_files = all_files,
        record_rel = "foo-1.0.dist-info/RECORD",
    )
    env.expect.that_bool(result == None).equals(True)

_tests.append(_test_fix_record_skips_whl_files)

def patch_whl_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
