"""hub_exposure tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:hub_exposure.bzl", "add_extras", "hub_exposure")  # buildifier: disable=bzl-visibility
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

def _configure(hub_name = "hub", dependency_groups = ["*"], pyproject_toml = None):
    return mocks.tag(
        hub_name = hub_name,
        dependency_groups = dependency_groups,
        pyproject_toml = pyproject_toml,
    )

def _module(name = "root", is_root = True, configure = []):
    return mocks.module(name = name, is_root = is_root, configure = configure)

def _exposure(*modules, hubs = None, default_pyproject = None):
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
    env.expect.that_dict(got.packages).contains_exactly({})

_tests.append(_test_not_configured)

def _test_configure(env):
    for groups, want in [
        (["*"], ["other_pkg", "simple"]),
        (["default"], ["simple"]),
        (["dev"], ["other_pkg"]),
        # `not-in-hub` is ignored
        (["group:test"], ["simple"]),
    ]:
        got, failures = _exposure(_module(configure = [_configure(dependency_groups = groups)]))
        env.expect.where(groups = groups).that_collection(failures).contains_exactly([])
        env.expect.where(groups = groups).that_dict(got.packages).contains_exactly({"hub": want})

_tests.append(_test_configure)

def _test_configure_all_packages(env):
    # Exposing all of the packages is the same as not configuring the hub, so
    # that e.g. the platform-specific packages stay public.
    got, failures = _exposure(_module(configure = [
        _configure(dependency_groups = ["default"]),
        _configure(dependency_groups = ["*", "transitive"]),
    ]))
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got.packages).contains_exactly({})

_tests.append(_test_configure_all_packages)

def _test_configure_combines_tags(env):
    got, failures = _exposure(_module(configure = [
        _configure(dependency_groups = ["default"]),
        _configure(dependency_groups = ["dev"]),
    ]))
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got.packages).contains_exactly({"hub": ["other_pkg", "simple"]})

_tests.append(_test_configure_combines_tags)

def _test_configure_pyproject_precedence(env):
    # The tag wins over the `pip.parse` value.
    got, _ = _exposure(_module(configure = [
        _configure(pyproject_toml = "other.toml"),
    ]))
    env.expect.that_dict(got.packages).contains_exactly({"hub": ["other_pkg"]})

    # The `pip.default` value is used for the hubs of the root module.
    got, failures = _exposure(
        _module(configure = [_configure(dependency_groups = ["default"])]),
        hubs = {"hub": _hub()},
        default_pyproject = "pyproject.toml",
    )
    env.expect.that_collection(failures).contains_exactly([])
    env.expect.that_dict(got.packages).contains_exactly({"hub": ["simple"]})

_tests.append(_test_configure_pyproject_precedence)

def _test_configure_module_precedence(env):
    hubs = {"hub": _hub(module_name = "dep", pyproject = "pyproject.toml")}

    # The owner of the hub can configure it.
    got, _ = _exposure(
        _module(),
        _module(name = "dep", is_root = False, configure = [_configure(dependency_groups = ["dev"])]),
        hubs = hubs,
    )
    env.expect.that_dict(got.packages).contains_exactly({"hub": ["other_pkg"]})

    # The root module wins over the owner.
    got, _ = _exposure(
        _module(configure = [_configure(dependency_groups = ["default"])]),
        _module(name = "dep", is_root = False, configure = [_configure(dependency_groups = ["dev"])]),
        hubs = hubs,
    )
    env.expect.that_dict(got.packages).contains_exactly({"hub": ["simple"]})

    # Other modules are ignored.
    got, _ = _exposure(
        _module(),
        _module(name = "other", is_root = False, configure = [_configure(dependency_groups = ["dev"])]),
        hubs = hubs,
    )
    env.expect.that_dict(got.packages).contains_exactly({})

_tests.append(_test_configure_module_precedence)

def _test_configure_extras(env):
    hubs = {"hub": _hub(pyproject = "extras.toml")}
    for groups, want in [
        (["default"], {"hub": {"simple": ["bar", "foo"]}}),
        # The packages that are not in the hub are ignored.
        (["dev"], {"hub": {"other_pkg": ["baz"], "simple": ["foo"]}}),
        # The extras are also exposed when all of the packages are exposed.
        (["*", "transitive"], {"hub": {"other_pkg": ["baz"], "simple": ["bar", "foo"]}}),
    ]:
        got, failures = _exposure(
            _module(configure = [_configure(dependency_groups = groups)]),
            hubs = hubs,
        )
        env.expect.where(groups = groups).that_collection(failures).contains_exactly([])
        env.expect.where(groups = groups).that_dict(got.extras).contains_exactly(want)

    # The extras of multiple tags are combined.
    got, _ = _exposure(
        _module(configure = [
            _configure(dependency_groups = ["default"]),
            _configure(dependency_groups = ["dev"]),
        ]),
        hubs = hubs,
    )
    env.expect.that_dict(got.extras).contains_exactly({
        "hub": {"other_pkg": ["baz"], "simple": ["bar", "foo"]},
    })

    # No extras are requested.
    got, _ = _exposure(_module(configure = [_configure()]))
    env.expect.that_dict(got.extras).contains_exactly({})

_tests.append(_test_configure_extras)

def _test_add_extras(env):
    whl_map = {
        "other_pkg": {"repo_other": [whl_config_setting(version = "3.15")]},
        "simple": {
            "repo_linux": [whl_config_setting(
                version = "3.15",
                target_platforms = ["cp315_linux_x86_64"],
                extras = ["bar"],
            )],
            "repo_osx": [whl_config_setting(
                version = "3.15",
                target_platforms = ["cp315_osx_aarch64"],
            )],
        },
    }
    got = add_extras(whl_map, {"simple": ["bar", "foo"]})
    env.expect.that_dict(got).contains_exactly({
        "other_pkg": {"repo_other": [whl_config_setting(version = "3.15")]},
        "simple": {
            "repo_linux": [whl_config_setting(
                version = "3.15",
                target_platforms = ["cp315_linux_x86_64"],
                extras = ["bar", "foo"],
            )],
            "repo_osx": [whl_config_setting(
                version = "3.15",
                target_platforms = ["cp315_osx_aarch64"],
                extras = ["bar", "foo"],
            )],
        },
    })

_tests.append(_test_add_extras)

def _test_configure_errors(env):
    _, failures = _exposure(_module(configure = [_configure(hub_name = "missing")]))
    env.expect.that_collection(failures).contains_exactly([
        "pip.configure() refers to unknown hub 'missing'. Available hubs: hub",
    ])

    _, failures = _exposure(
        _module(configure = [_configure()]),
        hubs = {"hub": _hub()},
    )
    env.expect.that_collection(failures).contains_exactly([
        "pip.configure() for hub 'hub' requires a pyproject.toml, set `pyproject_toml` on `pip.configure` or `pip.parse`",
    ])

_tests.append(_test_configure_errors)

def hub_exposure_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
