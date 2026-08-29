""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "subjects")
load("//python/private/pypi:register_whl_libraries.bzl", "register_whl_libraries")  # buildifier: disable=bzl-visibility

_tests = []

def _set_or_fail(store, kwargs):
    name = kwargs.pop("name")
    store[name] = kwargs

def _register_whl_libraries(env, registrations):
    whl_library_calls = {}
    whl_deps_repo_calls = {}
    whl_archive_calls = {}

    register_whl_libraries(
        registrations = registrations,
        rules = struct(
            whl_library = lambda **kwargs: _set_or_fail(whl_library_calls, kwargs),
            whl_deps_repo = lambda **kwargs: _set_or_fail(whl_deps_repo_calls, kwargs),
            whl_archive = lambda **kwargs: _set_or_fail(whl_archive_calls, kwargs),
        ),
    )

    return env.expect.that_struct(
        struct(
            whl_library_calls = whl_library_calls,
            whl_deps_repo_calls = whl_deps_repo_calls,
            whl_archive_calls = whl_archive_calls,
        ),
        attrs = dict(
            whl_library_calls = subjects.dict,
            whl_deps_repo_calls = subjects.dict,
            whl_archive_calls = subjects.dict,
        ),
    )

def _test_simple(env):
    got = _register_whl_libraries(
        env,
        registrations = {
            "name": {"dep_template": "bar"},
        },
    )

    # buildifier: @unsorted-dict-items
    got.whl_library_calls().contains_exactly({"name": {"dep_template": "bar"}})
    got.whl_deps_repo_calls().contains_exactly({})
    got.whl_archive_calls().contains_exactly({})

_tests.append(_test_simple)

def _whl_split(env):
    got = _register_whl_libraries(
        env,
        registrations = {
            # buildifier: @unsorted-dict-items
            "name": {
                "config_load": "config_load",
                "dep_template": "@hub_name//{name}:{pkg}",
                "filename": "pkg-0.0.1+deadbeef-py3-none-any.whl",
                "urls": ["url"],
                "index_url": "pypi",
                "integrity": "integrity",
                "requirement": "pkg[extra1]",
            },
        },
    )

    # buildifier: @unsorted-dict-items
    got.whl_library_calls().contains_exactly({})

    # buildifier: @unsorted-dict-items
    got.whl_deps_repo_calls().contains_exactly({"name": {
        "config_load": "config_load",
        "requirement": "pkg[extra1]",
        "dep_template": "@hub_name//{name}:{pkg}",
        "metadata_file": "@pkg_0_0_1_deadbeef_py3_none_any//:metadata.json",
    }})

    # buildifier: @unsorted-dict-items
    got.whl_archive_calls().contains_exactly({"pkg_0_0_1_deadbeef_py3_none_any": {
        "filename": "pkg-0.0.1+deadbeef-py3-none-any.whl",
        "urls": ["url"],
        "index_url": "pypi",
        "integrity": "integrity",
        "requirement": "pkg",
    }})

_tests.append(_whl_split)

def _per_hub_whl_split(env):
    got = _register_whl_libraries(
        env,
        registrations = {
            # buildifier: @unsorted-dict-items
            "name": {
                "config_load": "config_load",
                "dep_template": "@hub_name//{name}:{pkg}",
                "filename": "pkg-0.0.1-py3-none-any.whl",
                "urls": ["url"],
                "index_url": "pypi",
                "integrity": "integrity",
                "requirement": "pkg[extra1]",
            },
            "name2": {
                "config_load": "config_load",
                "dep_template": "@hub_name2//{name}:{pkg}",
                "filename": "pkg-0.0.1-py3-none-any.whl",
                "urls": ["url2"],
                "index_url": "private_index",
                "integrity": "integrity2",
                "requirement": "pkg[extra1]",
            },
        },
    )

    # buildifier: @unsorted-dict-items
    got.whl_library_calls().contains_exactly({})

    # buildifier: @unsorted-dict-items
    got.whl_deps_repo_calls().contains_exactly({
        "name": {
            "config_load": "config_load",
            "requirement": "pkg[extra1]",
            "dep_template": "@hub_name//{name}:{pkg}",
            "metadata_file": "@hub_name_pkg_0_0_1_py3_none_any//:metadata.json",
        },
        "name2": {
            "config_load": "config_load",
            "requirement": "pkg[extra1]",
            "dep_template": "@hub_name2//{name}:{pkg}",
            "metadata_file": "@hub_name2_pkg_0_0_1_py3_none_any//:metadata.json",
        },
    })

    # buildifier: @unsorted-dict-items
    got.whl_archive_calls().contains_exactly({
        "hub_name_pkg_0_0_1_deadbeef_py3_none_any": {
            "filename": "pkg-0.0.1-py3-none-any.whl",
            "urls": ["url"],
            "index_url": "pypi",
            "integrity": "integrity",
            "requirement": "pkg",
        },
        "hub_name2_pkg_0_0_1_py3_none_any": {
            "filename": "pkg-0.0.1-py3-none-any.whl",
            "urls": ["url2"],
            "index_url": "private_index",
            "integrity": "integrity2",
            "requirement": "pkg",
        },
    })

_tests.append(_per_hub_whl_split)

def register_whl_libraries_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
