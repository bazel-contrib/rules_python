""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("//python/private/pypi:pypi_cache.bzl", "pypi_cache")  # buildifier: disable=bzl-visibility

_tests = []

def _test_memory_cache_hit(env):
    """Verifies that the cache returns stored values for the same real_url."""
    store = {}

    # We pass None for module_ctx to focus solely on memory_cache behavior
    cache = pypi_cache(module_ctx = None, store = store)

    # Mocked parsed result from a PyPI-like index
    fake_result = struct(
        sdists = {
            "sha_1": struct(version = "1.0.0", filename = "pkg-1.0.0.tar.gz"),
        },
        whls = {
            "sha_2": struct(version = "1.1.0", filename = "pkg-1.1.0-py3-none-any.whl"),
        },
    )

    # Key format: (index_url, real_url, versions)
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.0.0", "1.1.0"])

    # When set the cache
    cache.setdefault(key, fake_result)

    # And get a value back
    got = cache.get(key)

    env.expect.that_dict(got.sdists).contains_exactly(fake_result.sdists)
    env.expect.that_dict(got.whls).contains_exactly(fake_result.whls)

_tests.append(_test_memory_cache_hit)

def pypi_cache_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
