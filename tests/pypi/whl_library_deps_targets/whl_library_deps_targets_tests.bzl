""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:whl_library_deps_targets.bzl", "whl_library_deps_targets")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

def _test_whl_library_deps_targets(env):
    filegroup_calls = []
    py_library_calls = []
    env_marker_setting_calls = []

    m_glob = mocks.glob()

    m_glob.results.append([])  # bin
    m_glob.results.append([])  # rewrite-bin
    m_glob.results.append(["site-packages/foo/SRCS.py"])  # srcs
    m_glob.results.append(["site-packages/foo/DATA.txt"])  # data
    m_glob.results.append(["site-packages/foo/PYI.pyi"])  # pyi

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "foo",  # this self-edge will be ignored
            "bar",
            "bar-baz; python_version < \"8.2\"",
            "booo",  # this is effectively excluded due to the list below
        ],
        include = ["foo", "bar", "bar_baz"],
        # Overrides for testing
        repo = None,
        aliases = None,
        extras = [],
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: None,
            config_setting = lambda **_: None,
            glob = m_glob.glob,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            create_inits = lambda *args, **kwargs: ["_create_inits_target"],
            venv_rewrite_shebang = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection(filegroup_calls).contains_exactly([
        {
            "name": "whl",
            # NOTE @aignas 2026-07-25: depending on the brackets position one may get different
            # results in the expectation.
            "srcs": ["whl_file"],
            "data": ["@pypi//bar:whl"] + select({
                ":is_include_bar_baz_true": ["@pypi//bar_baz:whl"],
                "//conditions:default": [],
            }),
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

    env.expect.that_collection(py_library_calls).has_size(1)
    if len(py_library_calls) != 1:
        return
    py_library_call = py_library_calls[0]

    env.expect.that_dict(py_library_call).contains_exactly({
        "name": "pkg",
        "srcs": ["srcs"],
        "deps": ["srcs", "@pypi//bar:pkg"] + select({
            ":is_include_bar_baz_true": ["@pypi//bar_baz:pkg"],
            "//conditions:default": [],
        }),
        "tags": [],
        "visibility": ["//visibility:public"],
    })  # buildifier: @unsorted-dict-items

    env.expect.that_collection(m_glob.calls).contains_exactly([])

    env.expect.that_collection(env_marker_setting_calls).contains_exactly([
        {
            "name": "include_bar_baz",
            "expression": "python_version < \"8.2\"",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_whl_library_deps_targets)

def _test_whl_library_deps_targets_no_deps(env):
    alias_calls = []
    filegroup_calls = []
    py_library_calls = []
    env_marker_setting_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [],
        group_name = "qux",
        repo = None,
        aliases = {},
        extras = [],
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: alias_calls.append(kwargs),
            config_setting = lambda **_: None,
            glob = lambda **_: [],
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
        ),
    )

    # If the package is in a group but has no deps, then the public labels should be aliases
    # to the srcs targets and no other targets should be created.
    env.expect.that_collection(alias_calls).contains_exactly([
        {
            "name": "pkg",
            "actual": "srcs",
            "visibility": ["//visibility:public"],
        },
        {
            "name": "whl",
            "actual": "whl_file",
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

    env.expect.that_collection(filegroup_calls).contains_exactly([])
    env.expect.that_collection(py_library_calls).contains_exactly([])
    env.expect.that_collection(env_marker_setting_calls).contains_exactly([])

_tests.append(_test_whl_library_deps_targets_no_deps)

def whl_library_deps_targets_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
