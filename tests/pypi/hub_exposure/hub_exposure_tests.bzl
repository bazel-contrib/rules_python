"""hub_exposure tests"""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load(
    "//python/private/pypi:hub_exposure.bzl",
    "hub_exposure",
)  # buildifier: disable=bzl-visibility
load("//tests/support/mocks:mocks.bzl", "mocks")

_tests = []

_PYPROJECT = """\
[project]
dependencies = ["simple"]

[dependency-groups]
dev = ["other-pkg"]
test = ["simple", "not-in-hub"]
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

def _exposure(*modules, hubs = None, default_pyproject = None):
    failures = []
    got = hub_exposure(
        mocks.mctx(
            modules = list(modules),
            mock_files = {
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
