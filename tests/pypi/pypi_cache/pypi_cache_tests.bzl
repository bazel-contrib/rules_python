""

load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:truth.bzl", "subjects")
load("//python/private/pypi:pypi_cache.bzl", "pypi_cache")  # buildifier: disable=bzl-visibility

_tests = []

def _cache(env, **kwargs):
    cache = pypi_cache(**kwargs)

    attrs = {
        "sdists": subjects.dict,
        "sha256s_by_version": subjects.dict,
        "whls": subjects.dict,
    }

    def _expect(value):
        if not value:
            return env.expect.that_str(value)

        return env.expect.that_struct(
            value,
            attrs = attrs,
        )

    return struct(
        setdefault = lambda *args, **kwargs: _expect(
            cache.setdefault(*args, **kwargs),
        ),
        get = lambda *args, **kwargs: _expect(
            cache.get(*args, **kwargs),
        ),
        get_facts = lambda: env.expect.that_dict(cache.get_facts()),
    )

def _test_memory_cache_hit(env):
    """Verifies that the cache returns stored values for the same real_url."""
    store = {}

    # We pass None for module_ctx to focus solely on memory_cache behavior
    cache = _cache(env, module_ctx = None, store = store)

    # Mocked parsed result from a PyPI-like index
    fake_result = struct(
        sdists = {
            "sha_1": struct(version = "1.0.0", filename = "pkg-1.0.0.tar.gz"),
        },
        whls = {
            "sha_2": struct(version = "1.1.0", filename = "pkg-1.1.0-py3-none-any.whl"),
        },
        sha256s_by_version = {
            "1.0.0": ["sha_1"],
            "1.1.0": ["sha_2"],
        },
    )

    # Key format: (index_url, real_url, versions)
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.0.0", "1.1.0"])

    # When set the cache
    cache.setdefault(key, fake_result)

    # And get a value back
    got = cache.get(key)

    got.sdists().contains_exactly(fake_result.sdists)
    got.whls().contains_exactly(fake_result.whls)
    got.sha256s_by_version().contains_exactly(fake_result.sha256s_by_version)

    # A different key with fewer versions
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.0.0"])

    got = cache.get(key)
    got.sdists().contains_exactly(fake_result.sdists)
    got.whls().contains_exactly({})
    got.sha256s_by_version().contains_exactly({"1.0.0": ["sha_1"]})

    # A key with no matches
    key = ("https://{PYPI_INDEX_URL}/pkg", "https://pypi.org/simple/pkg", ["1.2.0"])

    cache.get(key).equals(None)

_tests.append(_test_memory_cache_hit)

def _test_pypi_cache_writes_to_facts(env):
    """Verifies that setting a value in the cache also populates the facts store."""
    mock_ctx = struct(facts = {})
    cache = _cache(env, module_ctx = mock_ctx)

    fake_result = struct(
        sdists = {
            "sha_sdist": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0.tar.gz",
                url = "https://pypi.org/files/pkg-1.0.0.tar.gz",
                yanked = "",
            ),
        },
        whls = {
            "sha_whl": struct(
                version = "1.0.0",
                filename = "pkg-1.0.0-py3-none-any.whl",
                url = "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl",
                yanked = "Security issue",
            ),
        },
        sha256s_by_version = {
            "1.0.0": ["sha_sdist", "sha_whl"],
        },
    )

    key = ("https://{PYPI_INDEX_URL}/pkg/", "https://pypi.org/simple/pkg/", ["1.0.0"])

    # When we set the cache
    cache.setdefault(key, fake_result)

    # Then the key returns us the same items
    got = cache.get(key)
    got.whls().contains_exactly(fake_result.whls)
    got.sdists().contains_exactly(fake_result.sdists)
    got.sha256s_by_version().contains_exactly(fake_result.sha256s_by_version)

    # Then when we get facts at the end
    cache.get_facts().contains_exactly({
        "dist_hashes": {
            # We are not using the real index URL, because we may have credentials in here
            "https://{PYPI_INDEX_URL}": {
                "pkg": {
                    "https://pypi.org/files/pkg-1.0.0-py3-none-any.whl": "sha_whl",
                    "https://pypi.org/files/pkg-1.0.0.tar.gz": "sha_sdist",
                },
            },
        },
        "dist_yanked": {
            "https://{PYPI_INDEX_URL}": {
                "pkg": {
                    "sha_whl": "Security issue",
                },
            },
        },
        "fact_version": "v1",  # Facts version
    })

_tests.append(_test_pypi_cache_writes_to_facts)

def pypi_cache_test_suite(name):
    test_suite(
        name = name,
        basic_tests = _tests,
    )
