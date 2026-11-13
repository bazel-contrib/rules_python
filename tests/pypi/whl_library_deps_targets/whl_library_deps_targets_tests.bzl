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
        "precompile": "disabled",
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

def _test_extras(env):
    filegroup_calls = []
    py_library_calls = []
    env_marker_setting_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "bar",
            "grpc; extra == 'grpc'",
            "aiohttp; extra == 'async' and python_version < '3.12'",
            "uvloop; extra == 'async'",
            "foo[grpc]; extra == 'all'",
        ],
        provides_extra = ["async", "grpc", "all"],
        include = ["bar", "grpc", "aiohttp", "uvloop"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
        ),
    )

    # The `pkg` target has no extras because none were requested and there is
    # a target for each extra that the package provides. The `whl` target does
    # not use the extras.
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pypi//bar:pkg"]),
        ("[all]", ["srcs", "@pypi//bar:pkg", "@pypi//grpc:pkg"]),
        ("[async]", ["srcs", "@pypi//bar:pkg", "@pypi//uvloop:pkg"] + select({
            ":is_include_aiohttp_true": ["@pypi//aiohttp:pkg"],
            "//conditions:default": [],
        })),
        ("[grpc]", ["srcs", "@pypi//bar:pkg", "@pypi//grpc:pkg"]),
    ])
    env.expect.that_collection([
        (c["name"], c["data"])
        for c in filegroup_calls
    ]).contains_exactly([
        ("whl", ["@pypi//bar:whl"]),
    ])
    env.expect.that_collection(env_marker_setting_calls).contains_exactly([
        {
            "name": "include_aiohttp",
            "expression": "python_version < \"3.12\"",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_extras)

def _test_extras_with_different_markers(env):
    py_library_calls = []
    env_marker_setting_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "bar; sys_platform == 'win32'",
            "bar; extra == 'a' and sys_platform == 'linux'",
        ],
        provides_extra = ["a"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
        ),
    )

    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs"] + select({
            ":is_include_bar_true": ["@pypi//bar:pkg"],
            "//conditions:default": [],
        })),
        ("[a]", ["srcs"] + select({
            ":is_include_bar_2_true": ["@pypi//bar:pkg"],
            "//conditions:default": [],
        })),
    ])
    env.expect.that_collection([
        (c["name"], c["expression"])
        for c in env_marker_setting_calls
    ]).contains_exactly([
        ("include_bar", "sys_platform == \"win32\""),
        ("include_bar_2", "(sys_platform == \"linux\") or (sys_platform == \"win32\")"),
    ])

_tests.append(_test_extras_with_different_markers)

def _test_extras_no_deps(env):
    alias_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [],
        provides_extra = ["A"],
        repo = None,
        aliases = {},
        native = struct(
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(),
    )

    env.expect.that_collection([
        (c["name"], c["actual"])
        for c in alias_calls
    ]).contains_exactly([
        ("pkg", "srcs"),
        ("whl", "whl_file"),
        ("[a]", "srcs"),
    ])

_tests.append(_test_extras_no_deps)

def _test_extras_in_group(env):
    py_library_calls = []
    filegroup_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = ["baz", "bar; extra == 'a'", "qux; extra == 'a'"],
        provides_extra = ["a"],
        group_name = "group",
        # Only the `a` extra is in a cycle with `qux`.
        group_deps = ["Foo[A]", "qux"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
        ),
    )

    # Only the member targets exclude the other members and the targets are
    # visible to the hub that creates the group library.
    env.expect.that_collection([
        (c["name"], c["deps"], c["visibility"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pypi//baz:pkg"], ["@pypi//:__subpackages__"]),
        ("[a]", ["srcs", "@pypi//bar:pkg", "@pypi//baz:pkg"], ["@pypi//:__subpackages__"]),
    ])
    env.expect.that_collection([
        (c["name"], c["data"])
        for c in filegroup_calls
    ]).contains_exactly([
        ("whl", ["@pypi//baz:whl"]),
    ])

_tests.append(_test_extras_in_group)

def _test_extras_in_group_legacy(env):
    alias_calls = []
    py_library_calls = []
    filegroup_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pip_{name}//:{target}",
        requires_dist = ["qux", "bar; extra == 'a'"],
        provides_extra = ["a", "b"],
        group_name = "group",
        group_deps = ["foo", "foo[a]", "qux"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
        ),
    )

    # The member targets are implementation targets and the public targets
    # point to the group library in the config repo.
    env.expect.that_collection([
        (c["name"], c["actual"])
        for c in alias_calls
    ]).contains_exactly([
        ("pkg", "@pip__config//_groups:group_pkg"),
        ("[a]", "@pip__config//_groups:group_pkg"),
        ("whl", "@pip__config//_groups:group_whl"),
    ])
    env.expect.that_collection([
        (c["name"], c["deps"], c["visibility"])
        for c in py_library_calls
    ]).contains_exactly([
        ("_pkg", ["srcs"], ["@pip__config//_groups:__pkg__"]),
        ("_[a]", ["srcs", "@pip_bar//:pkg"], ["@pip__config//_groups:__pkg__"]),
        ("[b]", ["srcs", "@pip_qux//:pkg"], ["//visibility:public"]),
    ])
    env.expect.that_collection([
        (c["name"], c["data"], c["visibility"])
        for c in filegroup_calls
    ]).contains_exactly([
        ("_whl", [], ["@pip__config//_groups:__pkg__"]),
    ])

_tests.append(_test_extras_in_group_legacy)

def _test_deps_with_extras(env):
    filegroup_calls = []
    py_library_calls = []
    env_marker_setting_calls = []
    missing_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "bar[socks]",
            "baz[a,b]; sys_platform == 'linux'",
            "baz; sys_platform == 'darwin'",
            "qux[missing]",
        ],
        # The values are the extras that are available in the hub
        include = {
            "bar": ["socks"],
            "baz": ["a", "b"],
            "qux": [],
        },
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            missing_extra_error = lambda **kwargs: missing_calls.append(kwargs),
        ),
    )

    # The dependencies use the targets with the extras, the missing extras use
    # a target that fails the build with a helpful message.
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pypi//bar:[socks]", ":_missing_qux[missing]"] + select({
            ":is_include_baz_2_true": ["@pypi//baz:pkg"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[a]_true": ["@pypi//baz:[a]"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[b]_true": ["@pypi//baz:[b]"],
            "//conditions:default": [],
        })),
    ])
    env.expect.that_collection(missing_calls).contains_exactly([
        {
            "name": "_missing_qux[missing]",
            "package_name": "qux",
            "extra": "missing",
            "required_by": "foo",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items

    # The whl targets do not use the extras.
    env.expect.that_collection([
        (c["name"], c["data"])
        for c in filegroup_calls
    ]).contains_exactly([
        ("whl", ["@pypi//bar:whl", "@pypi//qux:whl"] + select({
            ":is_include_baz_true": ["@pypi//baz:whl"],
            "//conditions:default": [],
        })),
    ])
    env.expect.that_collection([
        (c["name"], c["expression"])
        for c in env_marker_setting_calls
    ]).contains_exactly([
        ("include_baz", "(sys_platform == \"darwin\") or (sys_platform == \"linux\")"),
        ("include_baz_2", "sys_platform == \"darwin\""),
        ("include_baz[a]", "sys_platform == \"linux\""),
        ("include_baz[b]", "sys_platform == \"linux\""),
    ])

_tests.append(_test_deps_with_extras)

def _test_deps_with_extras_without_hub_info(env):
    py_library_calls = []

    # When the dependencies refer to the whl repositories directly, then there
    # is no information about the available extras and the targets with the
    # extras in the dependency repositories are used.
    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi_{name}//:{target}",
        requires_dist = ["bar[socks]"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
        ),
    )

    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pypi_bar//:[socks]"]),
    ])

_tests.append(_test_deps_with_extras_without_hub_info)

def whl_library_deps_targets_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
