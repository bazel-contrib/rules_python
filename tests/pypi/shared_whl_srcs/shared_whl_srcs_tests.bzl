""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:shared_whl_srcs.bzl", "shared_whl_srcs")  # buildifier: disable=bzl-visibility

_tests = []

_URL = "https://files.pythonhosted.org/packages/foo-0.0.1-py3-none-any.whl"

def _whl(**kwargs):
    return {
        "config_load": "@pypi//:config.bzl",
        "dep_template": "@pypi//{name}:{target}",
        "filename": "foo-0.0.1-py3-none-any.whl",
        "index_url": "https://pypi.org/simple/foo",
        "integrity": "sha256-deadbeef",
        "requirement": "foo==0.0.1",
        "urls": [_URL],
    } | kwargs

def _test_shared_across_hubs(env):
    got = shared_whl_srcs(
        {
            "other_312_foo": _whl(
                config_load = "@other//:config.bzl",
                dep_template = "@other//{name}:{target}",
                group_name = "group",
                group_deps = ["foo", "bar"],
                requirement = "foo[extra]==0.0.1",
            ),
            "pypi_311_foo": _whl(),
            "pypi_312_foo": _whl(),
        },
        exclude = {},
    )

    env.expect.that_dict(got.srcs).contains_exactly({
        "whl_foo_0_0_1_py3_none_any": {
            "dep_template": "",
            "filename": "foo-0.0.1-py3-none-any.whl",
            "index_url": "https://pypi.org/simple/foo",
            "integrity": "sha256-deadbeef",
            "requirement": "foo",
            "urls": [_URL],
        },
    })
    env.expect.that_dict(got.deps).contains_exactly({
        "other_312_foo": {
            "config_load": "@other//:config.bzl",
            "dep_template": "@other//{name}:{target}",
            "group_deps": ["foo", "bar"],
            "group_name": "group",
            "metadata_file": "@whl_foo_0_0_1_py3_none_any//:metadata.json",
            "requirement": "foo[extra]==0.0.1",
        },
        "pypi_311_foo": {
            "config_load": "@pypi//:config.bzl",
            "dep_template": "@pypi//{name}:{target}",
            "metadata_file": "@whl_foo_0_0_1_py3_none_any//:metadata.json",
            "requirement": "foo==0.0.1",
        },
        "pypi_312_foo": {
            "config_load": "@pypi//:config.bzl",
            "dep_template": "@pypi//{name}:{target}",
            "metadata_file": "@whl_foo_0_0_1_py3_none_any//:metadata.json",
            "requirement": "foo==0.0.1",
        },
    })
    env.expect.that_dict(got.whl_libraries).contains_exactly({})

_tests.append(_test_shared_across_hubs)

def _test_first_index_url_wins(env):
    got = shared_whl_srcs(
        {
            "mirror_312_foo": _whl(
                index_url = "${PIP_INDEX_URL}/foo",
                envsubst = ["PIP_INDEX_URL"],
            ),
            "pypi_312_foo": _whl(),
        },
        exclude = {},
    )

    env.expect.that_dict(got.srcs).contains_exactly({
        "whl_foo_0_0_1_py3_none_any": {
            "dep_template": "",
            "envsubst": ["PIP_INDEX_URL"],
            "filename": "foo-0.0.1-py3-none-any.whl",
            "index_url": "${PIP_INDEX_URL}/foo",
            "integrity": "sha256-deadbeef",
            "requirement": "foo",
            "urls": [_URL],
        },
    })
    env.expect.that_collection(got.deps.keys()).contains_exactly([
        "mirror_312_foo",
        "pypi_312_foo",
    ])

_tests.append(_test_first_index_url_wins)

def _test_unique_by_url_and_integrity(env):
    got = shared_whl_srcs(
        {
            "a_312_foo": _whl(),
            "b_312_foo": _whl(integrity = "sha256-other"),
            "c_312_foo": _whl(urls = ["https://example.org/foo-0.0.1-py3-none-any.whl"]),
            # A relative URL is resolved against the unresolved index_url
            "d_312_foo": _whl(
                index_url = "${INDEX}/foo",
                urls = ["../../packages/foo-0.0.1-py3-none-any.whl"],
            ),
        },
        exclude = {},
    )

    env.expect.that_dict({
        name: args["metadata_file"]
        for name, args in got.deps.items()
    }).contains_exactly({
        "a_312_foo": "@whl_foo_0_0_1_py3_none_any//:metadata.json",
        "b_312_foo": "@whl_foo_0_0_1_py3_none_any_2//:metadata.json",
        "c_312_foo": "@whl_foo_0_0_1_py3_none_any_3//:metadata.json",
        "d_312_foo": "@whl_foo_0_0_1_py3_none_any_4//:metadata.json",
    })

_tests.append(_test_unique_by_url_and_integrity)

def _test_not_shared(env):
    excluded = _whl()
    patched = _whl(whl_patches = {"//:foo.patch": "{}"})
    annotated = _whl(annotation = "@whl_mods//:foo.json")
    no_integrity = _whl(integrity = "")
    sdist = _whl(filename = "foo-0.0.1.tar.gz")
    pip = {
        "dep_template": "@pypi//{name}:{target}",
        "requirement": "foo==0.0.1",
    }
    got = shared_whl_srcs(
        {
            "annotated": annotated,
            "excluded": excluded,
            "no_integrity": no_integrity,
            "patched": patched,
            "pip": pip,
            "sdist": sdist,
        },
        exclude = {"excluded": None},
    )

    env.expect.that_dict(got.srcs).contains_exactly({})
    env.expect.that_dict(got.deps).contains_exactly({})
    env.expect.that_dict(got.whl_libraries).contains_exactly({
        "annotated": annotated,
        "excluded": excluded,
        "no_integrity": no_integrity,
        "patched": patched,
        "pip": pip,
        "sdist": sdist,
    })

_tests.append(_test_not_shared)

def _test_different_extraction_args(env):
    other = _whl(pip_data_exclude = ["**/*.txt"])
    got = shared_whl_srcs(
        {
            "other_312_foo": other,
            "pypi_312_foo": _whl(),
        },
        exclude = {},
    )

    env.expect.that_collection(got.srcs.keys()).contains_exactly([
        "whl_foo_0_0_1_py3_none_any",
    ])
    env.expect.that_collection(got.deps.keys()).contains_exactly([
        "other_312_foo",
    ])
    env.expect.that_dict(got.whl_libraries).contains_exactly({
        "pypi_312_foo": _whl(),
    })

_tests.append(_test_different_extraction_args)

def _test_name_collision_with_whl_library(env):
    got = shared_whl_srcs(
        {
            "pypi_312_foo": _whl(),
            "whl_foo_0_0_1_py3_none_any": _whl(annotation = "@whl_mods//:foo.json"),
        },
        exclude = {},
    )

    env.expect.that_collection(got.srcs.keys()).contains_exactly([
        "whl_foo_0_0_1_py3_none_any_2",
    ])

_tests.append(_test_name_collision_with_whl_library)

def shared_whl_srcs_test_suite(name):
    """Create the test suite.

    Args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
