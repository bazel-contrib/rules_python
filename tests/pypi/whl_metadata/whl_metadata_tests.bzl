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
        readdir = lambda watch = None: [],
    )
    fail_messages = []
    find_whl_metadata(install_dir = fake_path, logger = struct(
        fail = fail_messages.append,
    ))
    env.expect.that_collection(fail_messages).contains_exactly([
        "The '*.dist-info' directory could not be found in 'site-packages'",
    ])

_tests.append(_test_empty)

def _test_contains_dist_info_but_no_metadata(env):
    fake_path = struct(
        basename = "site-packages",
        readdir = lambda watch = None: [
            struct(
                basename = "something.dist-info",
                is_dir = True,
                get_child = lambda basename: struct(
                    basename = basename,
                    exists = False,
                ),
            ),
        ],
    )
    fail_messages = []
    find_whl_metadata(install_dir = fake_path, logger = struct(
        fail = fail_messages.append,
    ))
    env.expect.that_collection(fail_messages).contains_exactly([
        "The METADATA file for the wheel could not be found in 'site-packages/something.dist-info'",
    ])

_tests.append(_test_contains_dist_info_but_no_metadata)

def whl_metadata_test_suite(name):  # buildifier: disable=function-docstring
    test_suite(
        name = name,
        basic_tests = _tests,
    )
