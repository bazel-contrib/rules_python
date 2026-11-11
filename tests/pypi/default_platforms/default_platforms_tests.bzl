"""Tests for the default pip platforms."""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python:versions.bzl", "PLATFORMS")
load("//python/private/pypi:default_platforms.bzl", "default_platforms")  # buildifier: disable=bzl-visibility

_tests = []

# The settings that select the variant of the toolchain distribution, which do
# not change the compatible wheels.
_IGNORED_SETTINGS = [
    "_is_py_pbs_distribution_",
]

def _normalize(labels):
    """Return the set of the canonical label strings.

    Args:
        labels: {type}`list[str | Label]` the labels to normalize.

    Returns:
        {type}`tuple[str]` the sorted canonical labels.
    """
    ret = {}
    for label in labels:
        label = Label(label)
        if any([s in label.name for s in _IGNORED_SETTINGS]):
            continue

        # `@platforms//os:macos` is an alias of `@platforms//os:osx`.
        if label.repo_name == "platforms" and label.package == "os" and label.name == "macos":
            label = Label("@platforms//os:osx")
        ret[str(label)] = None
    return tuple(sorted(ret))

def _test_all_toolchain_platforms_have_pip_platforms(env):
    pip_platforms = {
        _normalize(values["config_settings"]): name
        for name, values in default_platforms().items()
    }

    for name, platform in PLATFORMS.items():
        want = _normalize(platform.compatible_with + platform.target_settings)
        env.expect.where(
            toolchain_platform = name,
        ).that_str(
            pip_platforms.get(want, "<missing pip platform for {}>".format(want)),
        ).not_equals(
            "<missing pip platform for {}>".format(want),
        )

_tests.append(_test_all_toolchain_platforms_have_pip_platforms)

def _test_pip_platforms_are_unique(env):
    seen = {}
    for name, values in default_platforms().items():
        key = _normalize(values["config_settings"])
        env.expect.where(
            pip_platform = name,
        ).that_str(seen.get(key, name)).equals(name)
        seen[key] = name

_tests.append(_test_pip_platforms_are_unique)

def default_platforms_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
