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
            extra_select = lambda **kwargs: None,
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
    extra_select_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [],
        provides_extra = ["A"],
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
            extra_select = lambda **kwargs: extra_select_calls.append(kwargs),
        ),
    )

    # The packages depending on the extras of this package can still use them.
    env.expect.that_collection(extra_select_calls).contains_exactly([
        {
            "name": "_extras",
            "actual": select({
                ":_extras_a": ":[a]",
                "//conditions:default": ":pkg",
            }),
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

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
        {
            "name": "[a]",
            "actual": "srcs",
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
    extra_dep_calls = []
    extra_select_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "bar[socks]",
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
            config_setting = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            extra_dep = lambda **kwargs: extra_dep_calls.append(kwargs),
            extra_select = lambda **kwargs: extra_select_calls.append(kwargs),
        ),
    )

    # The `pkg` target has no extras because none were requested and there is
    # a target for each extra that the package provides. The `whl` target does
    # not use the extras. The dependencies on the extras of other packages use
    # the `_extras` target of the package, so that the hub does not need to
    # know about the extras.
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", ":_bar[socks]"]),
        ("[all]", ["srcs", ":_bar[socks]", "@pypi//grpc:pkg"]),
        ("[async]", ["srcs", ":_bar[socks]", "@pypi//uvloop:pkg"] + select({
            ":is_include_aiohttp_true": ["@pypi//aiohttp:pkg"],
            "//conditions:default": [],
        })),
        ("[grpc]", ["srcs", ":_bar[socks]", "@pypi//grpc:pkg"]),
    ])
    env.expect.that_collection(extra_dep_calls).contains_exactly([
        {
            "name": "_bar[socks]",
            "pkg": "@pypi//bar:_extras",
            "extra": "socks",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items
    env.expect.that_collection(extra_select_calls).contains_exactly([
        {
            "name": "_extras",
            "actual": select({
                ":_extras_all": ":[all]",
                ":_extras_async": ":[async]",
                ":_extras_grpc": ":[grpc]",
                "//conditions:default": ":pkg",
            }),
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items
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

def _test_extras_in_group(env):
    py_library_calls = []
    filegroup_calls = []
    extra_select_calls = []

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
            config_setting = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
            extra_select = lambda **kwargs: extra_select_calls.append(kwargs),
        ),
    )

    # The members of the group are selected via the group library in the hub.
    env.expect.that_collection([
        c["actual"]
        for c in extra_select_calls
    ]).contains_exactly([
        select({
            ":_extras_a": "@pypi//foo:[a]",
            "//conditions:default": ":pkg",
        }),
    ])

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
    extra_select_calls = []

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
            config_setting = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
            extra_select = lambda **kwargs: extra_select_calls.append(kwargs),
        ),
    )

    # The public targets of the members point to the group library.
    env.expect.that_collection([
        c["actual"]
        for c in extra_select_calls
    ]).contains_exactly([
        select({
            ":_extras_a": ":[a]",
            ":_extras_b": ":[b]",
            "//conditions:default": ":pkg",
        }),
    ])

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
    extra_dep_calls = []

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
        # The hub does not need to know which extras are available.
        include = {
            "bar": None,
            "baz": None,
            "qux": None,
        },
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: None,
            config_setting = lambda **kwargs: None,
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            extra_dep = lambda **kwargs: extra_dep_calls.append(kwargs),
            extra_select = lambda **kwargs: None,
        ),
    )

    # The dependencies on the extras use the `_extras` target of the packages
    # with the requested extra, which is resolved by the package that provides
    # it. If the package does not provide the extra, then only the package is
    # used.
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", ":_bar[socks]", ":_qux[missing]"] + select({
            ":is_include_baz_2_true": ["@pypi//baz:pkg"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[a]_true": [":_baz[a]"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[b]_true": [":_baz[b]"],
            "//conditions:default": [],
        })),
    ])
    env.expect.that_collection([
        (c["name"], c["pkg"], c["extra"])
        for c in extra_dep_calls
    ]).contains_exactly([
        ("_bar[socks]", "@pypi//bar:_extras", "socks"),
        ("_baz[a]", "@pypi//baz:_extras", "a"),
        ("_baz[b]", "@pypi//baz:_extras", "b"),
        ("_qux[missing]", "@pypi//qux:_extras", "missing"),
    ])

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

def whl_library_deps_targets_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
