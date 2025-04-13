""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:whl_metadata.bzl",
    "find_whl_metadata",
)  # buildifier: disable=bzl-visibility

_tests = []

def _test_empty(env):
    fake_path = struct(
        basename = "site-packages",
        readdir = lambda: [],
    )
    fail_messages = []
    find_whl_metadata(install_dir = fake_path, logger = struct(
        fail = fail_messages.append,
    ))
    env.expect.that_collection(fail_messages).contains_exactly([
        "The METADATA file for the wheel could not be found in 'site-packages'",
    ])

_tests.append(_test_empty)

def whl_metadata_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
