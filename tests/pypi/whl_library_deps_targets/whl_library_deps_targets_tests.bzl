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
        {
            "name": "[a]",
            "actual": "srcs",
            "visibility": ["//visibility:public"],
        },
        {
            "name": "[]",
            "actual": ":pkg",
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
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: env_marker_setting_calls.append(kwargs),
            extra_dep = lambda **kwargs: None,
        ),
    )

    # The `pkg` target has no extras because none were requested and there is
    # a target for each extra that the package provides. The `whl` target does
    # not use the extras. The dependencies on the extras of the other packages
    # use the `extra_dep` targets.
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

def _test_unknown_extras_in_hub(env):
    alias_calls = []
    py_library_calls = []
    warnings = []

    whl_library_deps_targets(
        name = "foo-1.0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [
            "bar",
            "grpc; extra == 'grpc'",
        ],
        provides_extra = ["grpc", "async"],
        # The hub requests the `grpc` extra and the `nope` extra that the
        # package does not provide.
        include = {"bar": [], "foo": ["grpc", "nope"], "grpc": []},
        tags = ["pypi_name=Foo", "pypi_version=1.0"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
            warn = warnings.append,
        ),
    )

    # The extras are not passed to the whl repositories of a hub, so the `pkg`
    # target does not include them. The extra that the package does not
    # provide is the same as the package without extras and results in a
    # warning, just like in `pip`.
    env.expect.that_collection([
        (c["name"], c["actual"])
        for c in alias_calls
    ]).contains_exactly([
        ("[]", ":pkg"),
    ])
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pypi//bar:pkg"]),
        ("[async]", ["srcs", "@pypi//bar:pkg"]),
        ("[grpc]", ["srcs", "@pypi//bar:pkg", "@pypi//grpc:pkg"]),
        ("[nope]", ["srcs", "@pypi//bar:pkg"]),
    ])
    env.expect.that_collection(warnings).contains_exactly([
        "WARNING: Foo 1.0 does not provide the extra 'nope'",
    ])

_tests.append(_test_unknown_extras_in_hub)

def _test_unknown_extras_in_hub_no_deps(env):
    alias_calls = []
    warnings = []

    whl_library_deps_targets(
        name = "foo-1.0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [],
        include = {"foo": ["nope"]},
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: None,
            env_marker_setting = lambda **kwargs: None,
            warn = warnings.append,
        ),
    )

    env.expect.that_collection([
        (c["name"], c["actual"])
        for c in alias_calls
    ]).contains_exactly([
        ("whl", "whl_file"),
        ("pkg", "srcs"),
        ("[nope]", "srcs"),
        ("[]", ":pkg"),
    ])
    env.expect.that_collection(warnings).contains_exactly([
        "WARNING: foo does not provide the extra 'nope'",
    ])

_tests.append(_test_unknown_extras_in_hub_no_deps)

def _test_requested_extras(env):
    alias_calls = []
    py_library_calls = []
    filegroup_calls = []
    warnings = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pip_{name}//:{target}",
        requires_dist = [
            "bar",
            "grpc; extra == 'grpc'",
            "uvloop; extra == 'async'",
        ],
        provides_extra = ["async", "grpc"],
        extras = ["Grpc", "nope"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: filegroup_calls.append(kwargs),
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
            warn = warnings.append,
        ),
    )
    env.expect.that_collection(warnings).contains_exactly([
        "WARNING: Foo does not provide the extra 'nope'",
    ])

    # The `pkg` target includes the requested extras, which is needed if there
    # is no hub to select the extras, and the `[]` target is the package
    # without extras. The requested extra that the package does not provide
    # does not have any dependencies, just like in `pip`.
    env.expect.that_collection(alias_calls).contains_exactly([])
    env.expect.that_collection([
        (c["name"], c["deps"])
        for c in py_library_calls
    ]).contains_exactly([
        ("pkg", ["srcs", "@pip_bar//:pkg", "@pip_grpc//:pkg"]),
        ("[]", ["srcs", "@pip_bar//:pkg"]),
        ("[async]", ["srcs", "@pip_bar//:pkg", "@pip_uvloop//:pkg"]),
        ("[grpc]", ["srcs", "@pip_bar//:pkg", "@pip_grpc//:pkg"]),
        ("[nope]", ["srcs", "@pip_bar//:pkg"]),
    ])
    env.expect.that_collection([
        (c["name"], c["data"])
        for c in filegroup_calls
    ]).contains_exactly([
        ("whl", ["@pip_bar//:whl"]),
    ])

_tests.append(_test_requested_extras)

def _test_requested_extras_no_deps(env):
    alias_calls = []
    py_library_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "Foo",
        dep_template = "@pypi//{name}:{target}",
        requires_dist = [],
        extras = ["nope"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
            warn = lambda _: None,
        ),
    )

    env.expect.that_collection([
        (c["name"], c["actual"])
        for c in alias_calls
    ]).contains_exactly([
        ("whl", "whl_file"),
        ("pkg", "srcs"),
        ("[nope]", "srcs"),
        ("[]", ":pkg"),
    ])
    env.expect.that_collection(py_library_calls).contains_exactly([])

_tests.append(_test_requested_extras_no_deps)

def _test_requested_extras_in_group_legacy(env):
    alias_calls = []
    py_library_calls = []

    whl_library_deps_targets(
        name = "foo-0-py3-none-any.whl",
        metadata_name = "foo",
        dep_template = "@pip_{name}//:{target}",
        requires_dist = ["qux", "bar; extra == 'a'", "baz; extra == 'a'"],
        provides_extra = ["a"],
        extras = ["a"],
        group_name = "group",
        group_deps = ["foo", "bar"],
        repo = None,
        aliases = {},
        native = struct(
            filegroup = lambda **kwargs: None,
            alias = lambda **kwargs: alias_calls.append(kwargs),
        ),
        rules = struct(
            py_library = lambda **kwargs: py_library_calls.append(kwargs),
            env_marker_setting = lambda **kwargs: None,
        ),
    )

    # The implementation target of the member includes the requested extras
    # and the package without extras is the group library.
    env.expect.that_collection([
        (c["name"], c["actual"], c["visibility"])
        for c in alias_calls
    ]).contains_exactly([
        ("pkg", "@pip__config//_groups:group_pkg", ["//visibility:public"]),
        ("whl", "@pip__config//_groups:group_whl", ["//visibility:public"]),
        ("[]", ":pkg", ["//visibility:public"]),
    ])
    env.expect.that_collection([
        (c["name"], c["deps"], c["visibility"])
        for c in py_library_calls
    ]).contains_exactly([
        ("_pkg", ["srcs", "@pip_baz//:pkg", "@pip_qux//:pkg"], ["@pip__config//_groups:__pkg__"]),
        ("[a]", ["srcs", "@pip_bar//:pkg", "@pip_baz//:pkg", "@pip_qux//:pkg"], ["//visibility:public"]),
    ])

_tests.append(_test_requested_extras_in_group_legacy)

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
        ("[]", ":pkg"),
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

def _targets(**kwargs):
    """Create the targets and return the calls to the rules.

    Args:
        **kwargs: the args for the `whl_library_deps_targets`.

    Returns:
        A struct with the `py_library` deps and the `whl` data by the target
        name and the calls to the other rules.
    """
    calls = struct(
        config_setting = [],
        env_marker_setting = [],
        extra_dep = [],
        extra_select = [],
        filegroup = [],
        py_library = [],
    )

    whl_library_deps_targets(
        name = "{}-1.0-py3-none-any.whl".format(kwargs["metadata_name"]),
        dep_template = kwargs.pop("dep_template", "@pypi//{name}:{target}"),
        repo = None,
        aliases = {},
        native = struct(
            alias = lambda **kwargs: None,
            config_setting = lambda **kwargs: calls.config_setting.append(kwargs),
            filegroup = lambda **kwargs: calls.filegroup.append(kwargs),
        ),
        rules = struct(
            env_marker_setting = lambda **kwargs: calls.env_marker_setting.append(kwargs),
            extra_dep = lambda **kwargs: calls.extra_dep.append(kwargs),
            extra_select = lambda **kwargs: calls.extra_select.append(kwargs),
            py_library = lambda **kwargs: calls.py_library.append(kwargs),
        ),
        **kwargs
    )

    return struct(
        deps = {c["name"]: c["deps"] for c in calls.py_library},
        whl_data = {c["name"]: c["data"] for c in calls.filegroup},
        env_markers = {c["name"]: c["expression"] for c in calls.env_marker_setting},
        extra_deps = calls.extra_dep,
        extra_selects = calls.extra_select,
        config_settings = [c["name"] for c in calls.config_setting],
    )

def _test_deps_with_extras(env):
    got = _targets(
        metadata_name = "foo",
        requires_dist = [
            "bar[socks]",
            "baz[a,b]; sys_platform == 'linux'",
            "baz; sys_platform == 'darwin'",
            "qux[not-requested]",
        ],
        # The values are the extras that are requested in the hub, which are
        # not needed for the extras of the dependencies.
        include = {
            "bar": ["socks"],
            "baz": ["a", "b"],
            "qux": [],
        },
    )

    # The extras of the dependencies are resolved by the packages that provide
    # them, so they are used via the `extra_dep` targets.
    env.expect.that_dict(got.deps).contains_exactly({
        "pkg": ["srcs", ":_bar[socks]", ":_qux[not_requested]"] + select({
            ":is_include_baz_2_true": ["@pypi//baz:pkg"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[a]_true": [":_baz[a]"],
            "//conditions:default": [],
        }) + select({
            ":is_include_baz[b]_true": [":_baz[b]"],
            "//conditions:default": [],
        }),
    })
    env.expect.that_collection(got.extra_deps).contains_exactly([
        {
            "name": "_" + dep,
            "deps": ["@pypi//{}:_extras".format(name)],
            "extra": extra,
            "visibility": ["//visibility:private"],
        }
        for dep, name, extra in [
            ("bar[socks]", "bar", "socks"),
            ("baz[a]", "baz", "a"),
            ("baz[b]", "baz", "b"),
            ("qux[not_requested]", "qux", "not_requested"),
        ]
    ])  # buildifier: @unsorted-dict-items

    # The whl targets do not use the extras.
    env.expect.that_dict(got.whl_data).contains_exactly({
        "whl": ["@pypi//bar:whl", "@pypi//qux:whl"] + select({
            ":is_include_baz_true": ["@pypi//baz:whl"],
            "//conditions:default": [],
        }),
    })
    env.expect.that_dict(got.env_markers).contains_exactly({
        "include_baz": "(sys_platform == \"darwin\") or (sys_platform == \"linux\")",
        "include_baz[a]": "sys_platform == \"linux\"",
        "include_baz[b]": "sys_platform == \"linux\"",
        "include_baz_2": "sys_platform == \"darwin\"",
    })

    # The package does not provide any extras.
    env.expect.that_collection(got.config_settings).contains_exactly([])
    env.expect.that_collection(got.extra_selects).contains_exactly([
        {
            "name": "_extras",
            "deps": [":[]"],
            "distribution": "foo",
            "extras": [],
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_deps_with_extras)

_COVERAGE_REQUIRES_DIST = [
    "tomli; python_full_version <= \"3.11.0a6\" and extra == \"toml\"",
]

def _test_extra_that_is_not_requested_in_the_hub(env):
    # The lock file has `coverage` without the `toml` extra, e.g. because the
    # extras are stripped when compiling the requirements.
    include = {"coverage": [], "pytest_cov": [], "tomli": []}

    got = _targets(
        metadata_name = "pytest-cov",
        requires_dist = ["coverage[toml]>=7.5", "pytest>=7"],
        include = include,
    )
    env.expect.that_dict(got.deps).contains_exactly({
        "pkg": ["srcs", ":_coverage[toml]"],
    })
    env.expect.that_collection(got.extra_deps).contains_exactly([
        {
            "name": "_coverage[toml]",
            "deps": ["@pypi//coverage:_extras"],
            "extra": "toml",
            "visibility": ["//visibility:private"],
        },
    ])  # buildifier: @unsorted-dict-items

    got = _targets(
        metadata_name = "coverage",
        requires_dist = _COVERAGE_REQUIRES_DIST,
        provides_extra = ["toml"],
        include = include,
        tags = ["pypi_name=coverage", "pypi_version=7.6.1"],
    )

    # Only the target of the extra has `tomli` and only for the Python
    # versions that need it, which is evaluated for each target platform.
    env.expect.that_dict(got.deps).contains_exactly({
        "[toml]": ["srcs"] + select({
            ":is_include_tomli_true": ["@pypi//tomli:pkg"],
            "//conditions:default": [],
        }),
        "pkg": ["srcs"],
    })
    env.expect.that_dict(got.env_markers).contains_exactly({
        "include_tomli": "python_full_version <= \"3.11.0a6\"",
    })
    env.expect.that_collection(got.config_settings).contains_exactly(["_extras_toml"])
    env.expect.that_collection(got.extra_selects).contains_exactly([
        {
            "name": "_extras",
            "deps": select({
                ":_extras_toml": [":[toml]"],
                "//conditions:default": [":[]"],
            }),
            "distribution": "coverage 7.6.1",
            "extras": ["toml"],
            "visibility": ["//visibility:public"],
        },
    ])  # buildifier: @unsorted-dict-items

_tests.append(_test_extra_that_is_not_requested_in_the_hub)

def _test_deps_of_the_extra_that_are_not_in_the_hub(env):
    # `tomli` is not locked, e.g. because the lock file is only for the Python
    # versions that do not need it. Like the other dependencies that are not
    # in the hub, it is dropped.
    got = _targets(
        metadata_name = "coverage",
        requires_dist = _COVERAGE_REQUIRES_DIST,
        provides_extra = ["toml"],
        include = {"coverage": [], "pytest_cov": []},
    )
    env.expect.that_dict(got.deps).contains_exactly({
        "[toml]": ["srcs"],
        "pkg": ["srcs"],
    })
    env.expect.that_dict(got.env_markers).contains_exactly({})

    # The same for the dependencies of the extra without any markers.
    got = _targets(
        metadata_name = "bar",
        requires_dist = ["baz; extra == \"x\"", "qux"],
        provides_extra = ["x"],
        include = {"bar": [], "foo": [], "qux": []},
    )
    env.expect.that_dict(got.deps).contains_exactly({
        "[x]": ["srcs", "@pypi//qux:pkg"],
        "pkg": ["srcs", "@pypi//qux:pkg"],
    })

    # Without any other dependencies the targets are aliases and the extra can
    # still be selected.
    got = _targets(
        metadata_name = "bar",
        provides_extra = ["x"],
        include = {"bar": [], "foo": []},
    )
    env.expect.that_dict(got.deps).contains_exactly({})
    env.expect.that_collection([
        (c["name"], c["extras"])
        for c in got.extra_selects
    ]).contains_exactly([("_extras", ["x"])])

_tests.append(_test_deps_of_the_extra_that_are_not_in_the_hub)

def _test_dep_with_extra_that_is_not_provided(env):
    include = {"bar": [], "foo": []}
    got = _targets(
        metadata_name = "foo",
        requires_dist = ["bar[nope]"],
        include = include,
    )

    # The package does not know the extras of its dependencies.
    env.expect.that_dict(got.deps).contains_exactly({
        "pkg": ["srcs", ":_bar[nope]"],
    })
    env.expect.that_collection([
        (c["deps"], c["extra"])
        for c in got.extra_deps
    ]).contains_exactly([(["@pypi//bar:_extras"], "nope")])

    # The `nope` extra is not in the `extras` of the `_extras` target, so it
    # selects the package without extras and prints a warning.
    got = _targets(
        metadata_name = "bar",
        requires_dist = ["baz; extra == \"x\""],
        provides_extra = ["x"],
        include = include,
    )
    env.expect.that_collection([
        (c["deps"], c["extras"])
        for c in got.extra_selects
    ]).contains_exactly([
        (
            select({
                ":_extras_x": [":[x]"],
                "//conditions:default": [":[]"],
            }),
            ["x"],
        ),
    ])

_tests.append(_test_dep_with_extra_that_is_not_provided)

def _test_self_referencing_extras_are_selected(env):
    got = _targets(
        metadata_name = "foo",
        requires_dist = [
            "foo[a,b]; extra == \"all\"",
            "dep-a; extra == \"a\"",
            "dep-b; extra == \"b\"",
        ],
        provides_extra = ["a", "all", "b"],
        include = {"dep_a": [], "dep_b": [], "foo": []},
    )

    # A dependency on `foo[all]` gets the dependencies of both extras and a
    # dependency on `foo[a]` only gets the ones of `a`.
    env.expect.that_dict(got.deps).contains_exactly({
        "[a]": ["srcs", "@pypi//dep_a:pkg"],
        "[all]": ["srcs", "@pypi//dep_a:pkg", "@pypi//dep_b:pkg"],
        "[b]": ["srcs", "@pypi//dep_b:pkg"],
        "pkg": ["srcs"],
    })
    env.expect.that_collection([c["deps"] for c in got.extra_selects]).contains_exactly([
        select({
            ":_extras_a": [":[a]"],
            ":_extras_all": [":[all]"],
            ":_extras_b": [":[b]"],
            "//conditions:default": [":[]"],
        }),
    ])
    env.expect.that_collection(got.extra_deps).contains_exactly([])

_tests.append(_test_self_referencing_extras_are_selected)

def _test_cycle_through_extras(env):
    # `a[x]` requires `b[y]` and `b[y]` requires `a[x]`. Each package only
    # reads its own `METADATA`, so nothing is resolved recursively here.
    a = dict(
        metadata_name = "a",
        requires_dist = ["b[y]; extra == \"x\""],
        provides_extra = ["x"],
        include = {"a": [], "b": []},
    )
    b = dict(
        metadata_name = "b",
        requires_dist = ["a[x]; extra == \"y\""],
        provides_extra = ["y"],
        include = {"a": [], "b": []},
    )

    # Without a group this is a dependency cycle between the targets like any
    # other cycle between the packages.
    env.expect.that_dict(_targets(**a).deps).contains_exactly({
        "[x]": ["srcs", ":_b[y]"],
        "pkg": ["srcs"],
    })
    env.expect.that_dict(_targets(**b).deps).contains_exactly({
        "[y]": ["srcs", ":_a[x]"],
        "pkg": ["srcs"],
    })

    # With the extras as the members of a group the cycle is broken and the
    # `_extras` targets select the group library of the hub.
    group = dict(group_name = "cycle", group_deps = ["a[x]", "b[y]"])
    got = _targets(**(a | group))
    env.expect.that_dict(got.deps).contains_exactly({
        "[x]": ["srcs"],
        "pkg": ["srcs"],
    })
    env.expect.that_collection(got.extra_deps).contains_exactly([])
    env.expect.that_collection([c["deps"] for c in got.extra_selects]).contains_exactly([
        select({
            ":_extras_x": ["@pypi//a:[x]"],
            "//conditions:default": [":[]"],
        }),
    ])
    got = _targets(**(b | group))
    env.expect.that_dict(got.deps).contains_exactly({
        "[y]": ["srcs"],
        "pkg": ["srcs"],
    })
    env.expect.that_collection(got.extra_deps).contains_exactly([])

_tests.append(_test_cycle_through_extras)

def _test_different_extras_of_the_same_dep(env):
    include = {"c": [], "foo_bar": [], "other_dep": [], "p": [], "q": [], "r": [], "tomli": []}

    # Each package only depends on the extra that it requires.
    got = _targets(metadata_name = "p", requires_dist = ["c[toml]"], include = include)
    env.expect.that_dict(got.deps).contains_exactly({"pkg": ["srcs", ":_c[toml]"]})
    env.expect.that_collection([
        (c["name"], c["deps"], c["extra"])
        for c in got.extra_deps
    ]).contains_exactly([("_c[toml]", ["@pypi//c:_extras"], "toml")])

    got = _targets(metadata_name = "q", requires_dist = ["c[other]"], include = include)
    env.expect.that_dict(got.deps).contains_exactly({"pkg": ["srcs", ":_c[other]"]})
    env.expect.that_collection([
        (c["name"], c["deps"], c["extra"])
        for c in got.extra_deps
    ]).contains_exactly([("_c[other]", ["@pypi//c:_extras"], "other")])

    got = _targets(
        metadata_name = "c",
        requires_dist = ["tomli; extra == \"toml\"", "other-dep; extra == \"other\""],
        provides_extra = ["toml", "other"],
        include = include,
    )
    env.expect.that_dict(got.deps).contains_exactly({
        "[other]": ["srcs", "@pypi//other_dep:pkg"],
        "[toml]": ["srcs", "@pypi//tomli:pkg"],
        "pkg": ["srcs"],
    })

    # The names of the packages and the extras are normalized on both sides.
    got = _targets(metadata_name = "r", requires_dist = ["Foo_Bar[TOML.Parser]"], include = include)
    env.expect.that_dict(got.deps).contains_exactly({"pkg": ["srcs", ":_foo_bar[toml_parser]"]})
    env.expect.that_collection([
        (c["name"], c["deps"], c["extra"])
        for c in got.extra_deps
    ]).contains_exactly([("_foo_bar[toml_parser]", ["@pypi//foo_bar:_extras"], "toml_parser")])

    got = _targets(
        metadata_name = "foo-bar",
        requires_dist = ["tomli; extra == \"toml-parser\""],
        provides_extra = ["toml-parser"],
        include = include,
    )
    env.expect.that_dict(got.deps).contains_exactly({
        "[toml_parser]": ["srcs", "@pypi//tomli:pkg"],
        "pkg": ["srcs"],
    })
    env.expect.that_collection(got.config_settings).contains_exactly(["_extras_toml_parser"])
    env.expect.that_collection([
        (c["deps"], c["extras"])
        for c in got.extra_selects
    ]).contains_exactly([
        (
            select({
                ":_extras_toml_parser": [":[toml_parser]"],
                "//conditions:default": [":[]"],
            }),
            ["toml_parser"],
        ),
    ])

_tests.append(_test_different_extras_of_the_same_dep)

def _test_extras_select_in_group_legacy(env):
    # Without a hub the members of the group are aliases to the group library
    # in the same repository.
    got = _targets(
        metadata_name = "foo",
        requires_dist = ["bar; extra == \"a\"", "qux; extra == \"b\""],
        provides_extra = ["a", "b"],
        group_name = "group",
        group_deps = ["foo[a]", "bar"],
        dep_template = "@pypi_{name}//:{target}",
    )
    env.expect.that_collection([c["deps"] for c in got.extra_selects]).contains_exactly([
        select({
            ":_extras_a": [":[a]"],
            ":_extras_b": [":[b]"],
            "//conditions:default": [":[]"],
        }),
    ])

_tests.append(_test_extras_select_in_group_legacy)

def whl_library_deps_targets_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
