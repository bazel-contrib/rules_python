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

def register_whl_libraries_test_suite(name):
    """create the test suite.

    args:
        name: the name of the test suite
    """
    test_suite(name = name, basic_tests = _tests)
