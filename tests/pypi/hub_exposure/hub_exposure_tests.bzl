"""hub_exposure tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:hub_exposure.bzl",
    "add_extras",
    "hub_exposure",
)  # buildifier: disable=bzl-visibility
load("//python/private/pypi:pep508_env.bzl", pep508_env = "env")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:render_pkg_aliases.bzl", "available_extras")  # buildifier: disable=bzl-visibility
load("//python/private/pypi:whl_config_setting.bzl", "whl_config_setting")  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

_PYPROJECT = """\
[project]
dependencies = ["simple"]

[dependency-groups]
dev = ["other-pkg"]
test = ["simple", "not-in-hub"]
"""

_EXTRAS_PYPROJECT = """\
[project]
dependencies = ["simple[foo]", "simple[Bar]; sys_platform == 'linux'"]

[dependency-groups]
dev = ["other-pkg[baz]", "simple[foo]", "not-in-hub[qux]"]
"""

def _hub(*, module_name = "root", pyproject = None):
    return struct(
        module_name = module_name,
        pyproject = pyproject,
        packages = ["other_pkg", "simple", "transitive_pkg"],
    )

def _configure(
        hub_name = "hub",
        dependency_groups = [],
        pyproject_toml = None):
    return mocks.tag(
        hub_name = hub_name,
        dependency_groups = dependency_groups,
        pyproject_toml = pyproject_toml,
    )

def _module(name = "root", is_root = True, configure = []):
    return mocks.module(name = name, is_root = is_root, configure = configure)

def _exposure(*modules, **kwargs):
    """Return the exposed packages of the hubs."""
    got, failures = _hub_exposure(*modules, **kwargs)
    return got.packages if got != None else None, failures

def _hub_exposure(*modules, hubs = None, default_pyproject = None):
    failures = []
    got = hub_exposure(
        mocks.mctx(
            modules = list(modules),
            mock_files = {
                "extras.toml": _EXTRAS_PYPROJECT,
                "other.toml": "[project]\ndependencies = [\"other-pkg\"]\n",
                "pyproject.toml": _PYPROJECT,
            },
        ),
        hubs = hubs or {"hub": _hub(pyproject = "pyproject.toml")},
        default_pyproject = default_pyproject,
        _fail = failures.append,
    )
    return got, failures

def _test_not_configured(env):
    got, failures = _exposure(_module())
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({})

_tests.append(_test_not_configured)

def _test_configure(env):
    for groups, want in [
        (["*"], ["other_pkg", "simple"]),
        (["default"], ["simple"]),
        (["dev"], ["other_pkg"]),
        # `not-in-hub` is ignored
        (["group:test"], ["simple"]),
    ]:
        got, failures = _exposure(
            _module(configure = [_configure(dependency_groups = groups)]),
        )
        env.expect.where(groups = groups).that_collection(
            failures,
        ).contains_exactly([])
        env.expect.where(groups = groups).that_dict(got).contains_exactly(
            {"hub": want},
        )

_tests.append(_test_configure)

def _test_configure_all_packages(env):
    # Exposing all of the packages is the same as not configuring the hub, so
    # that e.g. the platform-specific packages stay public.
    got, failures = _exposure(_module(configure = [
        _configure(dependency_groups = ["default"]),
        _configure(dependency_groups = ["*", "transitive"]),
    ]))
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({})

_tests.append(_test_configure_all_packages)

def _test_configure_combines_tags(env):
    got, failures = _exposure(_module(configure = [
        _configure(dependency_groups = ["default"]),
        _configure(dependency_groups = ["dev"]),
    ]))
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly(
        {"hub": ["other_pkg", "simple"]},
    )

_tests.append(_test_configure_combines_tags)

def _test_configure_pyproject_precedence(env):
    # The tag wins over the `pip.parse` value.
    got, _ = _exposure(_module(configure = [
        _configure(pyproject_toml = "other.toml", dependency_groups = ["*"]),
    ]))
    env.expect.that_dict(got).contains_exactly({"hub": ["other_pkg"]})

    # The `pip.default` value is used for the hubs of the root module.
    got, failures = _exposure(
        _module(configure = [_configure(dependency_groups = ["default"])]),
        hubs = {"hub": _hub()},
        default_pyproject = "pyproject.toml",
    )
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({"hub": ["simple"]})

_tests.append(_test_configure_pyproject_precedence)

def _test_configure_without_pyproject(env):
    # A tag without the dependency groups does not need a pyproject.toml and
    # does not limit the hub.
    got, failures = _exposure(
        _module(configure = [_configure()]),
        hubs = {"hub": _hub()},
    )
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({})

_tests.append(_test_configure_without_pyproject)

def _test_configure_builder(env):
    # The `pyproject_toml` of a tag is used by the later tags of the hub.
    got, failures = _exposure(
        _module(configure = [
            _configure(pyproject_toml = "other.toml"),
            _configure(dependency_groups = ["default"]),
        ]),
        hubs = {"hub": _hub(pyproject = "pyproject.toml")},
    )
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({"hub": ["other_pkg"]})

    # The tags before it use the `pip.parse` value.
    got, failures = _exposure(
        _module(configure = [
            _configure(dependency_groups = ["default"]),
            _configure(pyproject_toml = "other.toml", dependency_groups = ["default"]),
        ]),
        hubs = {"hub": _hub(pyproject = "pyproject.toml")},
    )
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got).contains_exactly({"hub": ["other_pkg", "simple"]})

    # It is not used by the other modules.
    hubs = {"hub": _hub(module_name = "dep")}
    got, failures = _exposure(
        _module(configure = [_configure(hub_name = "hub", pyproject_toml = "other.toml")]),
        _module(
            name = "dep",
            is_root = False,
            configure = [_configure(hub_name = "hub", dependency_groups = ["default"])],
        ),
        hubs = hubs,
    )
    env.expect.that_str(got).equals(None)
    env.expect.that_collection(failures).contains_exactly([
        "pip.configure() for hub 'hub' selects the dependency groups [\"default\"], which need a pyproject.toml, set `pyproject_toml` on this or an earlier `pip.configure` or on `pip.parse`",
    ])

_tests.append(_test_configure_builder)

def _test_configure_module_precedence(env):
    hubs = {"hub": _hub(module_name = "dep", pyproject = "pyproject.toml")}

    # The owner of the hub can configure it.
    got, _ = _exposure(
        _module(),
        _module(
            name = "dep",
            is_root = False,
            configure = [_configure(dependency_groups = ["dev"])],
        ),
        hubs = hubs,
    )
    env.expect.that_dict(got).contains_exactly({"hub": ["other_pkg"]})

    # The root module wins over the owner.
    got, _ = _exposure(
        _module(configure = [_configure(dependency_groups = ["default"])]),
        _module(
            name = "dep",
            is_root = False,
            configure = [_configure(dependency_groups = ["dev"])],
        ),
        hubs = hubs,
    )
    env.expect.that_dict(got).contains_exactly({"hub": ["simple"]})

    # Other modules are ignored.
    got, _ = _exposure(
        _module(),
        _module(
            name = "other",
            is_root = False,
            configure = [_configure(dependency_groups = ["dev"])],
        ),
        hubs = hubs,
    )
    env.expect.that_dict(got).contains_exactly({})

_tests.append(_test_configure_module_precedence)

def _test_configure_extras(env):
    hubs = {"hub": _hub(pyproject = "extras.toml")}
    linux = ("sys_platform == 'linux'",)
    for groups, want in [
        (["default"], {"hub": {"simple": {(): ["foo"], linux: ["bar"]}}}),
        # The packages that are not in the hub are ignored.
        (["dev"], {"hub": {"other_pkg": {(): ["baz"]}, "simple": {(): ["foo"]}}}),
        # The extras are also returned when all of the packages are exposed.
        (["*", "transitive"], {"hub": {
            "other_pkg": {(): ["baz"]},
            "simple": {(): ["foo"], linux: ["bar"]},
        }}),
    ]:
        got, failures = _hub_exposure(
            _module(configure = [_configure(dependency_groups = groups)]),
            hubs = hubs,
        )
        env.expect.where(groups = groups).that_collection(failures).contains_exactly([])
        env.expect.where(groups = groups).that_dict(got.extras).contains_exactly(want)

    # The extras of multiple tags are combined.
    got, _ = _hub_exposure(
        _module(configure = [
            _configure(dependency_groups = ["default"]),
            _configure(dependency_groups = ["dev"]),
        ]),
        hubs = hubs,
    )
    env.expect.that_dict(got.extras).contains_exactly({
        "hub": {
            "other_pkg": {(): ["baz"]},
            "simple": {(): ["foo"], linux: ["bar"]},
        },
    })

    # No extras are requested.
    got, _ = _hub_exposure(_module(configure = [_configure(dependency_groups = ["*"])]))
    env.expect.that_dict(got.extras).contains_exactly({})
    got, _ = _hub_exposure(_module(configure = [_configure()]))
    env.expect.that_dict(got.extras).contains_exactly({})

_tests.append(_test_configure_extras)

def _platforms(*platforms, version = "3.15"):
    """The marker environments of the hub platforms like `hub_builder` returns them."""
    return {
        version: {
            "cp{}_{}_{}".format(version.replace(".", ""), os, arch): pep508_env(
                os = os,
                arch = arch,
                python_version = version + ".0",
            )
            for os, arch in platforms
        },
    }

_LINUX = "cp315_linux_x86_64"
_OSX = "cp315_osx_aarch64"
_WINDOWS = "cp315_windows_x86_64"

def _test_add_extras(env):
    whl_map = {
        "other_pkg": {"repo_other": [whl_config_setting(version = "3.15")]},
        "simple": {
            "repo_linux": [whl_config_setting(
                version = "3.15",
                target_platforms = [_LINUX],
                extras = ["bar"],
            )],
            "repo_osx": [whl_config_setting(
                version = "3.15",
                target_platforms = [_OSX],
            )],
        },
    }
    got = add_extras(
        whl_map,
        {"simple": {(): ["bar", "foo"]}},
        platforms = _platforms(("linux", "x86_64"), ("osx", "aarch64")),
    )

    # The extras without markers are added on all of the platforms.
    env.expect.that_dict(got).contains_exactly({
        "other_pkg": {"repo_other": [whl_config_setting(version = "3.15")]},
        "simple": {
            "repo_linux": [whl_config_setting(
                version = "3.15",
                target_platforms = [_LINUX],
                extras = ["bar", "foo"],
            )],
            "repo_osx": [whl_config_setting(
                version = "3.15",
                target_platforms = [_OSX],
                extras = ["bar", "foo"],
            )],
        },
    })

    # Nothing to add.
    env.expect.that_dict(add_extras(whl_map, {}, platforms = {})).contains_exactly(whl_map)

_tests.append(_test_add_extras)

def _test_add_extras_markers(env):
    platforms = _platforms(("linux", "x86_64"), ("osx", "aarch64"), ("windows", "x86_64"))
    whl_map = {
        # A repo for all of the platforms, e.g. a pure Python wheel.
        "any": {"repo_any": [whl_config_setting(version = "3.15")]},
        "simple": {
            "repo_unix": [whl_config_setting(
                version = "3.15",
                target_platforms = [_LINUX, _OSX],
                extras = ["locked"],
            )],
            "repo_windows": [whl_config_setting(
                version = "3.15",
                target_platforms = [_WINDOWS],
            )],
        },
    }
    extras = {
        "any": {
            ("sys_platform == 'win32'",): ["win"],
            # All of the markers need to be true.
            ("python_version < '3.12'", "sys_platform == 'linux'"): ["old"],
        },
        "simple": {
            (): ["foo"],
            ("sys_platform == 'win32'",): ["win"],
            ("sys_platform == 'linux'",): ["lin"],
        },
    }

    got = add_extras(whl_map, extras, platforms = platforms)

    # `foo[win]; sys_platform == "win32"` only adds the extra on Windows, so
    # the other platforms do not get the dependencies of the extra, which may
    # not be available for them.
    env.expect.that_dict(got).contains_exactly({
        "any": {
            "repo_any": [
                whl_config_setting(
                    version = "3.15",
                    target_platforms = [_LINUX, _OSX],
                ),
                whl_config_setting(
                    version = "3.15",
                    target_platforms = [_WINDOWS],
                    extras = ["win"],
                ),
            ],
        },
        "simple": {
            "repo_unix": [
                whl_config_setting(
                    version = "3.15",
                    target_platforms = [_LINUX],
                    extras = ["foo", "lin", "locked"],
                ),
                whl_config_setting(
                    version = "3.15",
                    target_platforms = [_OSX],
                    extras = ["foo", "locked"],
                ),
            ],
            "repo_windows": [whl_config_setting(
                version = "3.15",
                target_platforms = [_WINDOWS],
                extras = ["foo", "win"],
            )],
        },
    })

    # The hub tells the whl repositories which extras are requested, so that
    # they create the targets for the extras that the package does not
    # provide, i.e. the hub never points to a target that does not exist.
    env.expect.that_dict(available_extras({
        name: {
            setting: repo
            for repo, settings in repos.items()
            for setting in settings
        }
        for name, repos in got.items()
    })).contains_exactly({
        "any": ["win"],
        "simple": ["foo", "lin", "locked", "win"],
    })

    # A marker that is the same on all of the platforms does not split the
    # config setting.
    got = add_extras(
        whl_map,
        {"any": {("python_version >= '3.12'",): ["new"], ("python_version < '3.12'",): ["old"]}},
        platforms = platforms,
    )
    env.expect.that_dict(got["any"]).contains_exactly({
        "repo_any": [whl_config_setting(version = "3.15", extras = ["new"])],
    })

    # Only the extras without markers are added if the platforms of the Python
    # version are not known.
    got = add_extras(whl_map, extras, platforms = {})
    env.expect.that_dict(got["any"]).contains_exactly(whl_map["any"])
    env.expect.that_dict(got["simple"]).contains_exactly({
        "repo_unix": [whl_config_setting(
            version = "3.15",
            target_platforms = [_LINUX, _OSX],
            extras = ["foo", "locked"],
        )],
        "repo_windows": [whl_config_setting(
            version = "3.15",
            target_platforms = [_WINDOWS],
            extras = ["foo"],
        )],
    })

_tests.append(_test_add_extras_markers)

def _test_configure_errors(env):
    got, failures = _exposure(
        _module(configure = [_configure(hub_name = "missing")]),
    )
    env.expect.that_str(got).equals(None)
    env.expect.that_collection(failures).contains_exactly([
        "pip.configure() refers to unknown hub 'missing'. Available hubs: hub",
    ])

    got, failures = _exposure(
        _module(configure = [_configure(dependency_groups = ["*"])]),
        hubs = {"hub": _hub()},
    )
    env.expect.that_str(got).equals(None)
    env.expect.that_collection(failures).contains_exactly([
        "pip.configure() for hub 'hub' selects the dependency groups [\"*\"], which need a pyproject.toml, set `pyproject_toml` on this or an earlier `pip.configure` or on `pip.parse`",
    ])

    got, failures = _exposure(
        _module(configure = [_configure(dependency_groups = ["missing"])]),
    )
    env.expect.that_str(got).equals(None)
    env.expect.that_collection(failures).contains_exactly([
        "Unknown dependency group 'missing'. Available groups: default, group:dev, group:test",
    ])

_tests.append(_test_configure_errors)

def hub_exposure_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
