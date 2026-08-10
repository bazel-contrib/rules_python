"""Tests for whl_extract."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:whl_extract.bzl", "rewrite_record_content")  # buildifier: disable=bzl-visibility

_tests = []

def _test_purelib_and_platlib_prefix_stripped(env):
    record = """\
foo-1.0.data/purelib/pkg/__init__.py,sha256=abc,100
foo-1.0.data/purelib/pkg/module.py,sha256=def,200
foo-1.0.data/platlib/pkg/_ext.so,sha256=ghi,300
foo-1.0.dist-info/METADATA,sha256=jkl,400
foo-1.0.dist-info/RECORD,,
"""
    result = rewrite_record_content(record, "foo-1.0.data")
    env.expect.that_str(result).equals("""\
pkg/__init__.py,sha256=abc,100
pkg/module.py,sha256=def,200
pkg/_ext.so,sha256=ghi,300
foo-1.0.dist-info/METADATA,sha256=jkl,400
foo-1.0.dist-info/RECORD,,
""")

_tests.append(_test_purelib_and_platlib_prefix_stripped)

def _test_data_headers_scripts_prefix_rewritten(env):
    record = """\
foo-1.0.data/data/pkg/data.txt,sha256=111,10
foo-1.0.data/headers/pkg/header.h,sha256=222,20
foo-1.0.data/scripts/my_script.sh,sha256=333,30
"""
    result = rewrite_record_content(record, "foo-1.0.data")
    env.expect.that_str(result).equals("""\
../../../pkg/data.txt,sha256=111,10
../../../include/pkg/header.h,sha256=222,20
../../../bin/my_script.sh,sha256=333,30
""")

_tests.append(_test_data_headers_scripts_prefix_rewritten)

def _test_quoted_paths_preserved(env):
    record = """\
"foo-1.0.data/purelib/pkg/my file.py",sha256=abc,100
"foo-1.0.data/scripts/my tool",sha256=def,200
"foo-1.0.data/headers/my header.h",sha256=ghi,300
"foo-1.0.data/data/my data.txt",sha256=jkl,400
"""
    result = rewrite_record_content(record, "foo-1.0.data")
    env.expect.that_str(result).equals("""\
"pkg/my file.py",sha256=abc,100
"../../../bin/my tool",sha256=def,200
"../../../include/my header.h",sha256=ghi,300
"../../../my data.txt",sha256=jkl,400
""")

_tests.append(_test_quoted_paths_preserved)

def _test_non_data_and_dist_info_entries_unchanged(env):
    record = """\
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/WHEEL,sha256=ccc,70
foo-1.0.dist-info/RECORD,,
"""
    result = rewrite_record_content(record, "foo-1.0.data")
    env.expect.that_str(result).equals("""\
top_level/__init__.py,sha256=aaa,50
foo-1.0.dist-info/METADATA,sha256=bbb,60
foo-1.0.dist-info/WHEEL,sha256=ccc,70
foo-1.0.dist-info/RECORD,,
""")

_tests.append(_test_non_data_and_dist_info_entries_unchanged)

def _test_unrecognized_data_category_preserved(env):
    record = """\
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
"""
    result = rewrite_record_content(record, "foo-1.0.data")
    env.expect.that_str(result).equals("""\
foo-1.0.data/custom_dir/custom.txt,sha256=xyz,123
""")

_tests.append(_test_unrecognized_data_category_preserved)

def whl_extract_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
