""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private:repo_utils.bzl", "REPO_DEBUG_ENV_VAR", "REPO_VERBOSITY_ENV_VAR", "repo_utils")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:select_whl.bzl", "select_whl")  # buildifier: disable=bzl-visibility

WHL_LIST = [
    "pkg-0.0.1-cp311-cp311-macosx_10_9_universal2.whl",
    "pkg-0.0.1-cp311-cp311-macosx_10_9_x86_64.whl",
    "pkg-0.0.1-cp311-cp311-macosx_11_0_arm64.whl",
    "pkg-0.0.1-cp311-cp311-manylinux_2_17_aarch64.manylinux2014_aarch64.whl",
    "pkg-0.0.1-cp311-cp311-manylinux_2_17_ppc64le.manylinux2014_ppc64le.whl",
    "pkg-0.0.1-cp311-cp311-manylinux_2_17_s390x.manylinux2014_s390x.whl",
    "pkg-0.0.1-cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    "pkg-0.0.1-cp311-cp311-manylinux_2_5_i686.manylinux1_i686.manylinux_2_17_i686.manylinux2014_i686.whl",
    "pkg-0.0.1-cp313-cp313t-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp313-cp313-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp313-abi3-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp313-none-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp311-cp311-musllinux_1_1_aarch64.whl",
    "pkg-0.0.1-cp311-cp311-musllinux_1_1_i686.whl",
    "pkg-0.0.1-cp311-cp311-musllinux_1_1_ppc64le.whl",
    "pkg-0.0.1-cp311-cp311-musllinux_1_1_s390x.whl",
    "pkg-0.0.1-cp311-cp311-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp311-cp311-win32.whl",
    "pkg-0.0.1-cp311-cp311-win_amd64.whl",
    "pkg-0.0.1-cp37-cp37m-macosx_10_9_x86_64.whl",
    "pkg-0.0.1-cp37-cp37m-manylinux_2_17_aarch64.manylinux2014_aarch64.whl",
    "pkg-0.0.1-cp37-cp37m-manylinux_2_17_ppc64le.manylinux2014_ppc64le.whl",
    "pkg-0.0.1-cp37-cp37m-manylinux_2_17_s390x.manylinux2014_s390x.whl",
    "pkg-0.0.1-cp37-cp37m-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    "pkg-0.0.1-cp37-cp37m-manylinux_2_5_i686.manylinux1_i686.manylinux_2_17_i686.manylinux2014_i686.whl",
    "pkg-0.0.1-cp37-cp37m-musllinux_1_1_aarch64.whl",
    "pkg-0.0.1-cp37-cp37m-musllinux_1_1_i686.whl",
    "pkg-0.0.1-cp37-cp37m-musllinux_1_1_ppc64le.whl",
    "pkg-0.0.1-cp37-cp37m-musllinux_1_1_s390x.whl",
    "pkg-0.0.1-cp37-cp37m-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp37-cp37m-win32.whl",
    "pkg-0.0.1-cp37-cp37m-win_amd64.whl",
    "pkg-0.0.1-cp39-cp39-macosx_10_9_universal2.whl",
    "pkg-0.0.1-cp39-cp39-macosx_10_9_x86_64.whl",
    "pkg-0.0.1-cp39-cp39-macosx_11_0_arm64.whl",
    "pkg-0.0.1-cp39-cp39-manylinux_2_17_aarch64.manylinux2014_aarch64.whl",
    "pkg-0.0.1-cp39-cp39-manylinux_2_17_ppc64le.manylinux2014_ppc64le.whl",
    "pkg-0.0.1-cp39-cp39-manylinux_2_17_s390x.manylinux2014_s390x.whl",
    "pkg-0.0.1-cp39-cp39-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    "pkg-0.0.1-cp39-cp39-manylinux_2_5_i686.manylinux1_i686.manylinux_2_17_i686.manylinux2014_i686.whl",
    "pkg-0.0.1-cp39-cp39-musllinux_1_1_aarch64.whl",
    "pkg-0.0.1-cp39-cp39-musllinux_1_1_i686.whl",
    "pkg-0.0.1-cp39-cp39-musllinux_1_1_ppc64le.whl",
    "pkg-0.0.1-cp39-cp39-musllinux_1_1_s390x.whl",
    "pkg-0.0.1-cp39-cp39-musllinux_1_1_x86_64.whl",
    "pkg-0.0.1-cp39-cp39-win32.whl",
    "pkg-0.0.1-cp39-cp39-win_amd64.whl",
    "pkg-0.0.1-cp39-abi3-any.whl",
    "pkg-0.0.1-py310-abi3-any.whl",
    "pkg-0.0.1-py3-abi3-any.whl",
    "pkg-0.0.1-py3-none-any.whl",
    # Extra examples that should be discarded
    "pkg-0.0.1-py27-cp27mu-win_amd64.whl",
    "pkg-0.0.1-pp310-pypy310_pp73-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
]

def _match(env, got, *want_filenames):
    if not want_filenames:
        env.expect.that_collection(got).has_size(len(want_filenames))
        return

    got = [g for g in got if g]
    got_filenames = [g.filename for g in got]
    env.expect.that_collection(got_filenames).contains_exactly(want_filenames).in_order()

    if got:
        # Check that we pass the original structs
        env.expect.that_str(got[0].other).equals("dummy")

def _select_whl(whls, debug = False, **kwargs):
    return select_whl(
        whls = [
            struct(
                filename = f,
                other = "dummy",
            )
            for f in whls
        ],
        logger = repo_utils.logger(struct(
            os = struct(
                environ = {
                    REPO_DEBUG_ENV_VAR: "1",
                    REPO_VERBOSITY_ENV_VAR: "TRACE" if debug else "INFO",
                },
            ),
        ), "unit-test"),
        **kwargs
    )

_tests = []

def _test_simplest(env):
    whls = [
        "pkg-0.0.1-py2.py3-abi3-any.whl",
        "pkg-0.0.1-py3-abi3-any.whl",
        "pkg-0.0.1-py3-none-any.whl",
    ]

    got = _select_whl(
        whls = whls,
        platforms = ["any"],
        whl_abi_tags = ["abi3"],
        python_version = "3.0",
    )
    _match(
        env,
        [got],
        "pkg-0.0.1-py3-abi3-any.whl",
    )

_tests.append(_test_simplest)

def _test_select_by_supported_py_version(env):
    whls = [
        "pkg-0.0.1-py2.py3-abi3-any.whl",
        "pkg-0.0.1-py3-abi3-any.whl",
        "pkg-0.0.1-py311-abi3-any.whl",
    ]

    for minor_version, match in {
        8: "pkg-0.0.1-py3-abi3-any.whl",
        11: "pkg-0.0.1-py311-abi3-any.whl",
    }.items():
        got = _select_whl(
            whls = whls,
            platforms = ["any"],
            whl_abi_tags = ["abi3"],
            python_version = "3.{}".format(minor_version),
        )
        _match(env, [got], match)

_tests.append(_test_select_by_supported_py_version)

def _test_select_by_supported_cp_version(env):
    whls = [
        "pkg-0.0.1-py2.py3-abi3-any.whl",
        "pkg-0.0.1-py3-abi3-any.whl",
        "pkg-0.0.1-py311-abi3-any.whl",
        "pkg-0.0.1-cp311-abi3-any.whl",
    ]

    for minor_version, match in {
        11: "pkg-0.0.1-cp311-abi3-any.whl",
        8: "pkg-0.0.1-py3-abi3-any.whl",
    }.items():
        got = _select_whl(
            whls = whls,
            platforms = ["any"],
            whl_abi_tags = ["abi3"],
            python_version = "3.{}".format(minor_version),
        )
        _match(env, [got], match)

_tests.append(_test_select_by_supported_cp_version)

def _test_supported_cp_version_manylinux(env):
    whls = [
        "pkg-0.0.1-py2.py3-none-manylinux_x86_64.whl",
        "pkg-0.0.1-py3-none-manylinux_x86_64.whl",
        "pkg-0.0.1-py311-none-manylinux_x86_64.whl",
        "pkg-0.0.1-cp311-none-manylinux_x86_64.whl",
    ]

    for minor_version, match in {
        8: "pkg-0.0.1-py3-none-manylinux_x86_64.whl",
        11: "pkg-0.0.1-cp311-none-manylinux_x86_64.whl",
    }.items():
        got = _select_whl(
            whls = whls,
            platforms = ["manylinux_x86_64"],
            whl_abi_tags = ["none"],
            python_version = "3.{}".format(minor_version),
        )
        _match(env, [got], match)

_tests.append(_test_supported_cp_version_manylinux)

def _test_ignore_unsupported(env):
    whls = ["pkg-0.0.1-xx3-abi3-any.whl"]
    got = _select_whl(
        whls = whls,
        platforms = ["any"],
        whl_abi_tags = ["none"],
        python_version = "3.0",
    )
    if got:
        _match(env, [got], None)

_tests.append(_test_ignore_unsupported)

def _test_match_abi_and_not_py_version(env):
    # Check we match the ABI and not the py version
    whls = WHL_LIST
    platforms = [
        "musllinux_*_x86_64",
        "manylinux_*_x86_64",
    ]
    got = _select_whl(
        whls = whls,
        platforms = platforms,
        whl_abi_tags = ["abi3", "cp37m"],
        python_version = "3.7",
    )
    _match(
        env,
        [got],
        "pkg-0.0.1-cp37-cp37m-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
    )

    got = _select_whl(
        whls = whls,
        platforms = platforms[::-1],
        whl_abi_tags = ["abi3", "cp37m"],
        python_version = "3.7",
    )
    _match(
        env,
        [got],
        "pkg-0.0.1-cp37-cp37m-musllinux_1_1_x86_64.whl",
    )

_tests.append(_test_match_abi_and_not_py_version)

def _test_select_filename_with_many_tags(env):
    # Check we can select a filename with many platform tags
    got = _select_whl(
        whls = WHL_LIST,
        platforms = [
            "any",
            "musllinux_*_i686",
            "manylinux_*_i686",
        ],
        whl_abi_tags = ["none", "abi3", "cp39"],
        python_version = "3.9",
        limit = 5,
    )
    _match(
        env,
        got,
        "pkg-0.0.1-py3-none-any.whl",
        "pkg-0.0.1-py3-abi3-any.whl",
        "pkg-0.0.1-cp39-abi3-any.whl",
        "pkg-0.0.1-cp39-cp39-musllinux_1_1_i686.whl",
        "pkg-0.0.1-cp39-cp39-manylinux_2_5_i686.manylinux1_i686.manylinux_2_17_i686.manylinux2014_i686.whl",
    )

_tests.append(_test_select_filename_with_many_tags)

def _test_freethreaded_wheels(env):
    # Check we prefer platform specific wheels
    got = _select_whl(
        whls = WHL_LIST,
        platforms = [
            "any",
            "musllinux_*_x86_64",
        ],
        whl_abi_tags = ["none", "abi3", "cp313", "cp313t"],
        python_version = "3.13",
        limit = 8,
    )
    _match(
        env,
        got,
        # The last item has the most priority
        "pkg-0.0.1-py3-none-any.whl",
        "pkg-0.0.1-py3-abi3-any.whl",
        "pkg-0.0.1-py310-abi3-any.whl",
        "pkg-0.0.1-cp39-abi3-any.whl",
        "pkg-0.0.1-cp313-none-musllinux_1_1_x86_64.whl",
        "pkg-0.0.1-cp313-abi3-musllinux_1_1_x86_64.whl",
        "pkg-0.0.1-cp313-cp313-musllinux_1_1_x86_64.whl",
        "pkg-0.0.1-cp313-cp313t-musllinux_1_1_x86_64.whl",
    )

_tests.append(_test_freethreaded_wheels)

def select_whl_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
